---
name: screenshot-fidelity-check
description: >
  Use to verify a UI screenshot matches a reference — a pure refactor
  (expect 0px) or a UIKit→SwiftUI migration (expect no cumulative layout
  drift). Both the implementing worker (self-check before claiming "done")
  and a supervisor (independent verification before merge) run THIS exact
  protocol. Triggers: "スクショ 一致確認", "before/after 比較", "視覚検証",
  "リファクタ前後 ピクセル", "移行 レイアウト確認", "screenshot diff",
  "visual regression", "PIL 罫線".
---

# Screenshot Fidelity Check

UI のスクリーンショットが参照画像と一致するかを**数値で**検証する単一の手順。
worker は「完了」を主張する前にこれを自分で実行し合格させる。supervisor は
マージ前に同じ手順を独立に再実行する（worker の自己申告を鵜呑みにしない）。

関連: [[supervising-worker-panes]] / 旧知見メモは各プロジェクトの memory 参照。

## 大原則: 目視判定 厳禁

`Read` ツールに表示される画像は縮小される。**縮小画像を目視で見比べてピクセル
差分を判定してはいけない** — 目視は再現性なく、同じ画像に対し毎回違う誤結論を出す。
`getbbox` / 差分ピクセル数 / 座標ズレの**数値**だけを根拠にする。「ほぼ一致」
「完全一致」を印象で言わない。ImageMagick は無い前提。PIL(Pillow) と `sips` を使う。

## 検証対象の 2 モードと合格基準

| モード | 例 | 合格基準 |
|---|---|---|
| **純粋リファクタ**（コンポーネント抽出・内部整理で挙動不変） | #115 #120 | `ImageChops.difference().getbbox()` が **`None`（0px 完全一致）**。ステータスバー時計以外の差分は回帰 |
| **移行**（UIKit→SwiftUI 等、実装が変わる） | #49 #106〜#109 | **(縦)** 全罫線を上から順にペアリングし全数 **±3px 以内**・罫線**本数一致**（累積レイアウトズレ無し）。**(横)** ラベル/コントロールの X 位置も **±3px 以内**。0〜3px はサブピクセル変動で実差分ではない |

## 手順

### 1. 全体差分（getbbox）

```python
from PIL import Image, ImageChops
b = Image.open("before.png").convert("RGB"); a = Image.open("after.png").convert("RGB")
assert b.size == a.size, f"寸法不一致 {b.size} vs {a.size}"
diff = ImageChops.difference(b, a)
print("getbbox:", diff.getbbox())          # None なら完全一致
amp = diff.point(lambda p: min(255, p*10)) # 10倍増幅
amp.save("/tmp/diff-amp.png")
```

純粋リファクタなら `getbbox` が `None` で合格・終了。非 None なら増幅画像を
`sips --resampleHeight 1300` で縮小して `Read` し、差分の**位置**を掴む。

### 2. 全画面・全罫線の Y 座標スキャン（移行モードの必須チェック）

**特定要素だけのサンプル計測は禁止** — 累積ドリフトはサンプルでは見えない
（#49 で worker が「行高 0 / ヘッダー +18 / TotalTime +14」と数点だけ測り、
全画面では +250px 累積していたのを見落とした）。必ず全幅罫線を全数測る:

```python
def find_seps(path):
    im = Image.open(path).convert("L"); W,H = im.size; px = im.load()
    # ステータスバー(上)と最下部を除外。1206x2622 iPhone 想定、端末で要調整
    rb = {y: sum(px[x,y] for x in range(200,W-200,5))//((W-400)//5) for y in range(140,H-60)}
    out=[]
    for y in range(146,H-66):
        nb=[rb[y+d] for d in (-6,-5,5,6) if y+d in rb]
        if nb and rb[y]-sum(nb)/len(nb) > 12: out.append(y)
    merged=[]
    for y in out:
        if merged and y-merged[-1][-1]<=4: merged[-1].append(y)
        else: merged.append([y])
    return [sum(g)//len(g) for g in merged]

bs, as_ = find_seps("before.png"), find_seps("after.png")
print(f"罫線本数 before={len(bs)} after={len(as_)}")
for i in range(min(len(bs),len(as_))):
    d = as_[i]-bs[i]
    print(f"  {i+1:2d}: {bs[i]:4d} / {as_[i]:4d}  ズレ={d:+d}{'  ★超過' if abs(d)>3 else ''}")
```

本数が違う / どこかでズレが急増したら、ペアリングを 1 ずらして再確認（検出器が
テキスト行を拾い 1 本ずれることがある）。1 ずらして全数 ±3px に収まるなら、
実体は「1 本の余分検出 or 欠落罫線」— その 1 本が実在の罫線か要確認。

### 2b. 水平ずれの検査（移行モードの必須チェック）

**罫線 Y スキャン（縦）だけでは一様な水平シフトを見逃す。** #53/#48 で、コンテンツ
全体が水平に約 10〜15px ずれていたのに罫線 Y は ±3px のまま素通りした。増幅画像で
テキストが横方向に二重化（"WWoorrkkoouutt" 状）して見えたら水平ずれの兆候。

縦が ±3px でも、`getbbox` がステータスバー時計以外で**非 None なら水平ずれを疑い**、
ラベル先頭 X を before/after で測る。**ただし「padding/inset の値そのもの」を知りたい
ときはピクセル測定でなくコードと storyboard XML を読む**（ピクセルの行検出はノイズが
多く -11/-60/+1 のように暴れる。`.padding(.leading, N)` や storyboard の
`<constraint constant>` は決定的）。原因切り分けは下記「fidelity 判断」を参照。

### 2c. テキストブロックの実測（フッター・複数行ラベル等の必須チェック）

**find_seps は画面横幅 80% を均等走査する全幅罫線検出器で、フッターの multi-line
text や局所的なテキストブロックの縦位置は見えない。** #125 で worker が
「background 0px PASS」と報告したが、フッターの注意書き複数行 Text が +16px 縦肥大
していたのを find_seps が見落とした実例あり。

`getbbox` 残差がテキスト領域（footer / multi-line label など）にあるなら、その帯の
**テキスト中心 Y を before/after で帯単位に実測**する。閾値は同じく ±3px:

```python
def text_bands(path, y0, y1):
    im = Image.open(path).convert("L"); W, H = im.size; px = im.load()
    bands=[]; inb=False; start=0
    for y in range(y0, y1):
        cnt = sum(1 for x in range(60, W-60, 3) if px[x, y] > 120)
        if cnt > 15 and not inb: inb = True; start = y
        elif cnt <= 15 and inb: inb = False; bands.append((start, y-1, (start+y-1)//2))
    if inb: bands.append((start, y1-1, (start+y1-1)//2))
    return bands  # 各帯の (top, bottom, center_y)
```

`y0/y1` で対象セクション（フッター等）の Y 範囲を絞り、before/after で帯リストを取り、
**i 番目の帯の center_y を before vs after で比較**して全帯 ±3px を確認する。
#125 background は body 全 5 行が修正前 +16〜17px、修正後 ±1px へ収束した。

SwiftUI 多行テキストが UIKit より縦肥大する典型原因は **`Text` に `.frame(height:)` 未指定**。
DESIGN.md の縦レイアウトガイドラインどおり各 `Text` に公称行高を `.frame(height:)` で
明示すれば収まる。

### 2d. アイコン/SF Symbol の bbox W×H 実測（描画サイズ差の必須チェック）

**罫線 Y / 水平 X / テキスト帯 Center Y はすべて「位置」軸で、アイコンの描画サイズ
（W×H）は見えない。** 実際に Play/Pause/Stop アイコンが
before 36×41 / 39×39 → after 83×94 / 88×93（約 2.3 倍）に肥大していたが、中心 Y が
一致するため worker・supervisor 両方の自動検査をすり抜け、ユーザー目視で発覚した例がある。

ボタン群やナビバーアイコンが含まれる画面は、各アイコン領域内で **明色ピクセルの
bbox（min/max XY → W=max-min）を before/after で実測**する。同種アイコン群の中で
一部だけ肥大/縮小していたら（PR #132 では Backward/Forward 66×37 で 0px 差・中央 2 つ
だけ 2.3 倍）非対称性が決定打。閾値は同じく ±3px:

```python
def icon_box(path, xr, yr, threshold=200):  # 暗背景の白アイコンは threshold=200
    from PIL import Image
    im = Image.open(path).convert("L"); px = im.load()
    pts = [(x,y) for y in range(*yr) for x in range(*xr) if px[x,y] > threshold]
    if not pts: return None
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys), max(xs)-min(xs), max(ys)-min(ys))

sizes = {}
for name, xr in [("Play",(380,540)),("Stop",(640,800)),("Back",(130,270)),("Fwd",(920,1080))]:
    bb = icon_box("before.png", xr, (1700,1900))
    ab = icon_box("after.png",  xr, (1700,1900))
    if bb and ab:
        sizes[name] = (ab[4], ab[5])
        print(f"{name}: before W×H={bb[4]}×{bb[5]} / after W×H={ab[4]}×{ab[5]} "
              f"Δ=W{ab[4]-bb[4]:+d} H{ab[5]-bb[5]:+d}")

# 同種要素群の非対称性検出（同じレイアウトロールのアイコン中で外れ値を抽出）
# PR #132 では Backward/Forward 66×37 と Play/Stop 83×94 で W が約 +20 離れていた
# のが肥大の決定打だった。中央値から離れた要素を機械的に拾う:
if sizes:
    ws = sorted(s[0] for s in sizes.values())
    med_w = ws[len(ws)//2]
    for name, (w, h) in sizes.items():
        if abs(w - med_w) > 10:
            print(f"⚠ {name} W={w} は中央値 {med_w} から {w-med_w:+d}px 外れ — "
                  f"非対称（肥大/縮小疑い）")
```

明背景の暗アイコン（黒シンボル）は `px[x,y] < 60` 等で閾値を反転する。同種ボタン群
内で **W/H が一致しない** ものを優先的に直す。SwiftUI で SF Symbol が肥大する典型原因は
`.font(.system(size:))` 指定不足 / `.imageScale(.large)` 既定値の漏れ / `Image(systemName:)`
に `.resizable().frame(width:height:)` を付けて意図しないサイズになっている等。

### 2e. 色 hex サンプリング（色トークン適用画面の必須チェック）

**位置軸（罫線 Y / 水平 X / テキスト帯 Y / アイコン bbox W×H）はすべて「どこにあるか／
どの大きさか」を見るが、「色そのもの」は見えない。** DESIGN.md 準拠化や色トークン
切り替え系の修正では、代表座標で 1 ピクセル hex を抽出して `before / after / 参照画面`
の 3 者比較が必要。例えば背景 `#F2F2F7 → #58535E` /
カード `#FFFFFF → #58535E` / ラベル `systemBlue → #F9F4FF` / ナビバー
`#2D2A30 維持` のように hex で参照画面と一致確認する。

```python
def hex_at(im, x, y):
    p = im.getpixel((x,y)); return f"#{p[0]:02X}{p[1]:02X}{p[2]:02X}"

# 代表座標で before / after / 参照画面 (DESIGN.md 準拠の既存画面) を 3 者比較
b = Image.open("before.png").convert("RGB")
a = Image.open("after.png").convert("RGB")
r = Image.open("reference.png").convert("RGB")  # 例: TimerSetting 等の準拠画面

# サンプル位置は画面サイズ依存。背景は中央、カードは行内、navbar は上端、accent はラベル
samples = [
    ("画面背景",      a.size[0]//2, a.size[1]//2),
    ("カード内側",     a.size[0]//4, 450),
    ("ナビバー",      a.size[0]//2, 100),
    ("accent ラベル", int(a.size[0]*0.2), 700),
]
print(f"{'位置':22s} {'before':10s} {'after':10s} {'reference':10s} 一致?")
for name, x, y in samples:
    bh, ah, rh = hex_at(b,x,y), hex_at(a,x,y), hex_at(r,x,y)
    ok = "✅" if ah == rh else "❌"
    print(f"{name:22s} {bh:10s} {ah:10s} {rh:10s} {ok}")
```

合格基準: **統一トークン適用画面では `after == reference` が hex 単位で一致**（1 ピクセル
精度）。`before != after && after == reference` なら正しい統一化、`after != reference` なら
トークン取り違え/未適用。アンチエイリアス境界を踏まないようサンプル座標は塗りつぶし
領域の内側に取る。グラデーション/影は単点比較不可なので領域平均を取る。

### 3. 差分箇所のクロップ確認

差分が残る領域は `sips -c <h> <w> --cropOffset <top> <left> in.png --out crop.png`
で before/after からクロップし、高解像度で内容を確認する。

## 移行モードの fidelity 判断（重要）

移行画面は旧 Storyboard と**完全な pixel-match を絶対基準にしない**。
`DESIGN.md` と共通コンポーネントの統一値が正準。

- **累積崩れ・行高・セクション構成のズレ**は実バグ → 厳密に直す。
- **個々の要素の数 px 差が旧 Storyboard 自体の不統一に由来する**なら追従しない
  （#49: 旧の Sets 行だけラベルが 12px 余分にインセットされていた。新画面は統一
  15px が正しい）。切り分け方: 同種要素（セルラベル等）の X/Y を複数測り、旧側が
  バラついていれば「旧の不統一」、新側だけズレていれば「新のバグ」。

## 完了ゲート

worker は「完了」「マージ準備完了」を主張する**前に**本手順を実行し、上表の合格
基準を満たすことを数値出力で示す。満たさなければ完了ではない。supervisor は
マージ前に同手順を独立再実行する。worker prompt にはこの skill 実行を完了条件
として明記する。

**罫線 Y が ±3px でも、`getbbox` がステータスバー時計以外で非 None の限り「合格」に
しない。** 残差の正体（水平ずれ・バーグラフ等の要素差）を必ず特定し、「実バグなので
直した」か「旧 Storyboard の不統一なので DESIGN.md 統一値を採り意図的に追従しない」の
どちらかを数値・根拠つきで言い切る。縦の罫線チェックだけ通して完了宣言しない。

## 「測ったらその場でコミット」— 不可分化（必須）

**PIL の数値表だけ出して画像本体を `git add` し忘れる事故が頻発する**（複数 PR で連続発生した実績あり）。worker prompt に「コミット必須」と書くだけでは効きが弱い。
**この skill を呼んだら、測定の同じターン内で git commit まで到達することを完了の定義に
含める**:

```bash
DATE=$(date +%Y-%m-%d)
SCREEN=<画面名 小文字 ハイフン>          # 例: workoutsetting / timer / background
DST=docs/superpowers/plans/screenshots

# 1) before/after 画像本体
cp /tmp/<work>/before.png $DST/$DATE-$SCREEN-before.png
cp /tmp/<work>/after.png  $DST/$DATE-$SCREEN-after.png

# 2) 数値結果を md にまとめる（罫線 Y / 水平 X / テキスト帯 / アイコン bbox / 色 hex 全 5 軸）
cat > $DST/$DATE-$SCREEN-comparison.md << 'EOF'
# <screen> 視覚検証 (yyyy-mm-dd, <commit-sha>)
## 罫線 Y
...
## アイコン bbox W×H
...
## 色 hex
...
EOF

# 3) 同じターン内で commit
git add $DST/$DATE-$SCREEN-*.png $DST/$DATE-$SCREEN-comparison.md
git commit -m "docs: <screen> 視覚検証スクショと数値結果を追加 (#<issue>)"

# 4) 検証: ファイルが HEAD に入ったか
git ls-tree HEAD -- $DST/$DATE-$SCREEN-* | wc -l   # 期待値: 3 以上
```

「PR を作る／完了サマリを出す」前に上記コミットが HEAD に乗っていることを必ず確認する。
supervisor 独立検証時もこのコミットされた PNG を `git show <branch>:path > /tmp/...` で
取り出して再検証する（worker のローカルファイルに頼らない）。
