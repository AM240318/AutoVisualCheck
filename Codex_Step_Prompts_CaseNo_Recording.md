# Codex向けファイル別・段階実装プロンプト

この文書は、統合実装をファイル単位で安全に進めるためのプロンプト集です。

各Stepは前段のインターフェースを前提とします。途中で引数数、マーカー名、フォルダ名、終了コード方針を勝手に変更しないでください。仕様の基準は`Codex_Master_Prompt_CaseNo_Recording.md`です。

## 全Step共通の固定ルール

- 従来方式と新方式を共存させる。
- 変更対象は`VERI.can`、`START_REC.bat`、`STOP_REC.bat`、新規`START_REC2.bat`、`START_REC3.bat`、`STOP_REC2.bat`。
- `MM_前進ミラー開_153Cases.txt`は変更しない。
- `obs_record_start.ps1`、`obs_record_stop.ps1`は変更しない。
- `VERI.cbf`、`VERIsysvar.vsysvar`は変更しない。
- BATとOBS用PowerShellは実行しない。静的確認だけを行う。
- 共通ログファイルを作らない。画面へ`[INFO]`、`[WARN]`、`[ERROR]`を表示する。
- BATは失敗を隠して常に0にしない。処理失敗があれば最終的に`exit /b 1`。
- ただし、途中の失敗で独立処理を止めない。特にSTOP系はCAN、OBS、Tera Termの停止をすべて試行する。
- ファイルが見つからないだけなら警告であり、他にエラーがなければ0。
- OBS開始・停止にはBAT側から20秒の外側タイムアウトを設ける。
- STOP順はCAN -> OBS -> Tera Term -> 3秒待機 -> 保存先準備 -> ファイル移動。
- Tagは`^[A-Za-z0-9_-]+$`だけを許可し、すべて大文字へ正規化する。
- CaseNoは1以上の10進整数。最低3桁ゼロ埋め。1000以上は切り捨てない。
- Repeatは1以上の10進整数で、ゼロ埋めしない。
- すべてのパスを二重引用符で囲む。
- 無期限待機、`pause`、確認入力、無関係なリファクタリングを行わない。

---

# Step 0：現状調査だけを行うプロンプト

以下のファイルを読み、まだ変更せずに実装計画を報告してください。

```text
VERI.can
START_REC.bat
STOP_REC.bat
obs_record_start.ps1
obs_record_stop.ps1
MM_前進ミラー開_153Cases.txt
VERIsysvar.vsysvar
```

確認事項：

1. `VERI.can`の`CASENO`、`REPEAT`、`GAIBU`処理の現在位置と内容。
2. `START_REC.bat`のOBS、CAN、COM42 Tera Term、スクリーンショットの順序と待ち時間。
3. `STOP_REC.bat`のCAN、OBS、COM42 Tera Term、アーカイブの順序と、OBS失敗時の早期終了箇所。
4. OBS用PowerShellの呼び出し方法と、現状無期限待機になり得る箇所。
5. 現在使われている実パス、ウィンドウタイトル、キー操作。
6. `VERI.can`の文字コードがCP932系、改行がCRLFであること。
7. `VERI::Case1`、`VERI::Case2`、`VERI::RepCNT1`が既存であること。

報告には、変更予定ファイル、新規ファイル、変更禁止ファイル、想定リスクを含めてください。BATやPowerShellは実行しないでください。

---

# Step 1：`VERI.can`だけを変更するプロンプト

`VERI.can`だけを最小差分で変更してください。他のファイルは変更しないでください。

## 目的

`CASENO`パラメータ1、`CASENO`パラメータ2、`REPEAT`パラメータ1を、BAT名ごとに必要な数だけ`sysExec`第2引数へ渡します。

## 既存処理を維持

次の意味を維持してください。

```text
CASENO パラメータ1 -> VERI::Case1 -> CaseNo
CASENO パラメータ2 -> VERI::Case2 -> Tag
REPEAT パラメータ1 -> VERI::RepCNT1 -> 現在のRepeat番号
```

既存の`Case2`、`RepCNT2`設定を削除しないでください。

## GAIBU引数表

`scrParam1`の実行ファイルのベース名を大文字小文字を無視して判定してください。

| BAT | 渡す引数 |
|---|---|
| `START_REC.bat` | `"CaseNo" "Tag"` |
| `START_REC2.bat` | 空文字 |
| `START_REC3.bat` | `"CaseNo" "Tag"` |
| `STOP_REC.bat` | `"CaseNo" "Tag"` |
| `STOP_REC2.bat` | `"CaseNo" "Tag" "Repeat"` |
| その他 | 空文字 |

例：

```text
START_REC.bat "1" "WB"
START_REC2.bat
START_REC3.bat "1" "WB"
STOP_REC.bat "1" "WB"
STOP_REC2.bat "1" "WB" "2"
```

## 必須動作

- GAIBU実行時に`VERI::Case1`、`VERI::Case2`、`VERI::RepCNT1`を取得する。
- CaseNo、Tag、Repeatが空でもBAT呼び出しを中止しない。
- CAPL側では値をフォールバックへ変換しない。生の値を引用符付きでBATへ渡す。
- `sysExec`の起動結果を理由にテスト処理を中断しない。
- 現行と同様にGAIBUコマンドを処理済みとして次へ進める。
- Writeウィンドウへ次を表示する。

```text
commandline:<実行ファイル> args:<引数または<none>>
```

- GAIBUを録画専用ロジックにしない。
- パネル側の別ハンドラや他の外部コマンド処理へ影響させない。
- ファイル名判定は単純な部分一致ではなく、可能ならベース名の完全一致にする。

## バッファと互換性

- 必要な固定長バッファだけを`variables`ブロックへ追加する。
- `snprintf()`がこのCAPL環境で利用可能か確認する。
- 利用不可なら、既存環境で使える安全な文字列関数を使う。
- バッファ長を超えないようにする。

## 文字コード

- `/*@!Encoding:932*/`を維持する。
- CP932／Shift-JIS系を維持する。
- CRLFを維持する。
- UTF-8へ変換しない。
- 無関係な行を再整形しない。

## 完了報告

- 変更概要
- unified diff
- 対象BAT別の生成引数例
- CP932／CRLF確認結果
- CANoeコンパイルが必要であること
- BATを実行していないこと

---

# Step 2：`START_REC.bat`だけを変更するプロンプト

既存`START_REC.bat`だけを変更してください。他のファイルは変更しないでください。

## インターフェース

```text
%1 = CaseNo
%2 = Tag
```

## 維持する既存順序

```text
OBS録画開始
↓
CANログ開始
↓
COM42 Tera Termログ開始
↓
Windowsキー + PrintScreen
```

現行のnircmdパス、ウィンドウタイトル、キー操作、既存待ち時間を不用意に変えないでください。到達不能なCOM39処理を整理しないでください。

## 検証・正規化

CaseNo：

- 1以上の10進整数
- `1`と`001`は同じ数値
- 最低3桁表示
- 1000以上を切り捨てない

Tag：

- `^[A-Za-z0-9_-]+$`
- 大文字へ正規化

引数不正でもOBS、CAN、Tera Term、スクリーンショットを可能な限り試行してください。危険な値をパスやコマンドへ連結しないでください。

## マーカー

```bat
set "LEGACY_SESSION_FILE=%~dp0legacy_session.marker"
```

`KEY=VALUE`形式で最低限、次を保存してください。

```text
Version=1
SessionId=<GUID>
ArgsValid=0または1
CaseNoCanonical=<有効時の数値。不正時はUNKNOWN>
TagNormalized=<有効時の大文字Tag。不正時はUNKNOWN>
SessionStartTimeUtc=<UTC ISO 8601>
VideoStartTimeUtc=<UTC ISO 8601>
LogStartTimeUtc=<UTC ISO 8601>
ObsStartSucceeded=0または1
```

時刻：

- `SessionStartTimeUtc`はBAT開始直後
- `VideoStartTimeUtc`はOBS開始呼び出し直前
- `LogStartTimeUtc`はCANログ開始操作直前

マーカーは古い同名ファイルを上書きしてください。可能なら一時ファイルからの置換で部分書き込みを避けてください。

## OBS開始

- 現行`obs_record_start.ps1`を変更せずに使う。
- BAT側から20秒の外側タイムアウトを設ける。
- タイムアウト時は子PowerShellを終了する。
- OBS開始失敗またはタイムアウトでも、CANログ、Tera Term、スクリーンショットを続ける。
- OBS開始失敗時もマーカーを削除せず、`ObsStartSucceeded=0`を記録する。

## 終了コード

- 引数不正、マーカー書込み失敗、OBS開始失敗、nircmd起動失敗等があれば、最後に`exit /b 1`。
- 全処理成功なら0。
- OBS失敗直後の早期終了は禁止。
- 共通ログファイルを作らない。

## 静的確認

- 既存操作順を維持している。
- OBS失敗でも後続へ進む。
- マーカーに全必須キーがある。
- 20秒タイムアウトが有限である。
- BATを実行していない。

完了時にunified diffと実機確認項目を提示してください。

---

# Step 3：`START_REC2.bat`を新規作成するプロンプト

`START_REC2.bat`を新規作成してください。他のファイルは変更しないでください。

## インターフェース

引数なしです。CaseNo、Tag、Repeatを受け取る仕様にしないでください。

## 責務

既存`START_REC.bat`の処理を参照し、次だけを実装してください。

```text
CANログ開始
↓
COM42 Tera Termログ開始
↓
Windowsキー + PrintScreen
```

次は禁止です。

- OBS開始
- 親フォルダ作成
- Repeat子フォルダ作成
- ファイル移動

## マーカー

```bat
set "LOG_SESSION_FILE=%~dp0log_session.marker"
```

最低限：

```text
Version=1
SessionId=<新規GUID>
SessionStartTimeUtc=<UTC ISO 8601>
LogStartTimeUtc=<UTC ISO 8601>
```

- `SessionStartTimeUtc`はBAT開始直後
- `LogStartTimeUtc`はCANログ開始操作直前
- 起動ごとに古いマーカーを上書き

## エラー継続

- CAN開始失敗でもTera Term開始とスクリーンショットを試行する。
- Tera Term開始失敗でもスクリーンショットを試行する。
- `nircmd.exe`不足や操作起動失敗をエラーとして保持する。
- 途中の早期`exit /b 1`を使わない。
- 内部エラーありなら最後に1、成功なら0。
- 共通ログファイルを作らない。

## 既存互換

- `START_REC.bat`と同じMeasurement Setupタイトル、COM42タイトル、キー操作、実行パス、既存待ち時間を使う。
- COM39や無関係な処理を新規に追加しない。

## 完了報告

- 新規ファイル全文またはunified diff
- 既存`START_REC.bat`から流用した処理一覧
- マーカーキー一覧
- 静的確認
- 実機確認項目
- BAT未実行の明記

---

# Step 4：`START_REC3.bat`を新規作成するプロンプト

`START_REC3.bat`を新規作成してください。他のファイルは変更しないでください。

## インターフェース

```text
%1 = CaseNo
%2 = Tag
```

Repeatは受け取りません。

## 責務

```text
CaseNo／Tag親フォルダを作成または再利用
↓
OBS録画開始
```

次は禁止です。

- CANログ開始
- Tera Termログ開始
- スクリーンショット
- Repeat子フォルダ作成
- ファイル移動

## 正常な親フォルダ

CaseNo=`1`、Tag=`wb`：

```text
C:\Users\TMC\Desktop\LogZips\Case001_WB
```

- Tagは大文字へ正規化。
- 親フォルダがあれば削除、退避、初期化せず再利用。
- 親フォルダ作成失敗でもOBS開始を試行。
- 引数不正でもOBS開始を試行。
- 不正な入力をフォルダ名へ連結しない。

## セッション連携

`%~dp0log_session.marker`を安全に読み取ってください。

- 有効なSessionIdがあれば引き継ぐ。
- ない／壊れている場合は新規GUIDを発行する。
- この異常を保持し、最終的に終了コード1。ただしOBS開始は試行する。

## 動画マーカー

```bat
set "VIDEO_SESSION_FILE=%~dp0video_session.marker"
```

最低限：

```text
Version=1
SessionId=<引継ぎまたは新規GUID>
ArgsValid=0または1
CaseNoCanonical=<有効時の数値。不正時はUNKNOWN>
TagNormalized=<有効時の大文字Tag。不正時はUNKNOWN>
VideoStartTimeUtc=<UTC ISO 8601>
ObsStartSucceeded=0または1
```

## OBS開始

- 既存`obs_record_start.ps1`を変更しない。
- BAT側から20秒の外側タイムアウト。
- タイムアウト時は子PowerShellを終了。
- OBS開始失敗でもマーカーを残し、`ObsStartSucceeded=0`を記録。
- 親フォルダ失敗や引数不正でもOBS開始を試行。

## 終了コード

- 引数不正、親フォルダ作成失敗、ログマーカー連携失敗、動画マーカー書込み失敗、OBS開始失敗等があれば最終的に1。
- 成功なら0。
- 共通ログファイルを作らない。

完了時に新規ファイル、unified diff、正常／異常フロー、実機確認項目を提示してください。BATは実行しないでください。

---

# Step 5：`STOP_REC.bat`だけを変更するプロンプト

既存`STOP_REC.bat`だけを変更してください。他のファイルは変更しないでください。

## インターフェース

```text
%1 = CaseNo
%2 = Tag
```

## 必須順序

```text
引数・legacy_session.marker読込み
STOP日時をローカル時刻で1回取得
↓
CANログ停止
↓
OBS録画停止（BAT側20秒上限）
↓
COM42 Tera Termログ停止
↓
3秒待機
↓
保存先作成
↓
ファイル選別・リネーム・移動
↓
legacy_session.marker削除
↓
最終サマリーと終了コード
```

現行のOBS停止直後にある早期`exit /b 1`をなくしてください。OBS停止失敗でもTera Term停止とアーカイブを続けてください。

## 引数・一致判定

- CaseNoは1以上の10進整数。数値比較で`1`と`001`は一致。
- Tagは`^[A-Za-z0-9_-]+$`、大文字へ正規化。
- マーカーのCaseNo／TagとSTOP側を比較。

正常一致：正常命名。

引数不正、マーカーの`ArgsValid=0`、または開始・停止不一致：有効な開始マーカー時刻で今回分を検索するが、STOP側Case名は使わず日時だけのフォールバック命名。終了コード1。

## 正常命名

CaseNo=`1`、Tag=`WB`、日時=`20260717_143025`：

```text
C:\Users\TMC\Desktop\LogZips\Case001_WB_20260717_143025
├─ Case001_WB.mp4
├─ Case001_WB_<元名>.png
├─ Case001_WB_<元名>.log
└─ Case001_WB_<元名>.asc
```

## フォールバック命名

```text
C:\Users\TMC\Desktop\LogZips\20260717_143025
├─ 20260717_143025.mp4
├─ 20260717_143025_<元名>.png
├─ 20260717_143025_<元名>.log
└─ 20260717_143025_<元名>.asc
```

## 有効マーカー時の選別

| 種類 | 条件 |
|---|---|
| MP4 | `CreationTimeUtc >= VideoStartTimeUtc` |
| PNG | `CreationTimeUtc >= SessionStartTimeUtc` |
| LOG | `LastWriteTimeUtc >= LogStartTimeUtc` |
| ASC | `LastWriteTimeUtc >= LogStartTimeUtc` |

- MP4候補複数：最新1件だけ。
- PNG／LOG／ASC：条件一致すべて。
- 条件一致0件：警告のみ。単純な最新へフォールバックしない。
- `ObsStartSucceeded=0`：MP4を移動せず、最新MP4へもフォールバックしない。ログ系は続ける。終了コード1。

## マーカーなし／破損時

STOP側引数が正常なら正常命名を使い、各種類の最新1件だけを移動してください。

| 種類 | 最新判定 |
|---|---|
| MP4 | CreationTimeUtc |
| PNG | CreationTimeUtc |
| LOG | LastWriteTimeUtc |
| ASC | LastWriteTimeUtc |

マーカー欠落・破損自体はエラーなので、移動成功でも最終的に1。

## ファイル処理

- MP4は選定した1件を指定名へ変更して移動。
- PNG／LOG／ASCは元ファイル名を残し、接頭辞を付ける。
- ワイルドカードを無条件に`move`しない。
- 1件失敗でも他ファイルと他拡張子を続ける。
- 対象0件だけなら終了コード0。
- 保存先作成失敗時はファイルを元場所へ残し、終了コード1。
- STOP日時が同一秒で完全同名の保存先が既にある場合は既存フォルダへ追加せず、保存先準備失敗として移動を中止し、終了コード1。
- 既存ファイルを無条件上書きしない。

## マーカー削除

成功・失敗にかかわらず最後に削除を試行。削除失敗だけなら警告で0のまま。

## 完了報告

- unified diff
- 正常一致、不一致、マーカーなし、OBS開始失敗の各フロー
- 保存例
- 静的確認
- 実機確認項目
- BAT未実行の明記

---

# Step 6：`STOP_REC2.bat`を新規作成するプロンプト

`STOP_REC2.bat`を新規作成してください。他のファイルは変更しないでください。

## インターフェース

```text
%1 = CaseNo
%2 = Tag
%3 = 現在のRepeat番号
```

## 必須順序

```text
引数・log_session.marker・video_session.marker読込み
STOP日時をローカル時刻で1回取得
↓
CANログ停止
↓
OBS録画停止（BAT側20秒上限）
↓
COM42 Tera Termログ停止
↓
3秒待機
↓
親フォルダ準備
↓
同一Case／Tag／Repeatの直前通常子フォルダ1件をOLD退避
↓
新しい子フォルダ作成
↓
ファイル選別・リネーム・移動
↓
2種類のマーカー削除
↓
最終サマリーと終了コード
```

保存先準備を停止操作より前に行わないでください。保存先で失敗しても、停止操作はすべて試行済みになる構成にしてください。

## 検証・正規化

- CaseNo：1以上の10進整数、最低3桁、1000以上を切り捨てない。
- Tag：`^[A-Za-z0-9_-]+$`、大文字化。
- Repeat：1以上の10進整数、ゼロ埋めなし。

CaseNo、Tag、Repeatのいずれか不正、または動画マーカーの`ArgsValid=0`なら新方式のフォールバックを使い、終了コード1。

## 正常命名

CaseNo=`1`、Tag=`wb`、Repeat=`2`、日時=`20260717_143025`：

```text
C:\Users\TMC\Desktop\LogZips
└─ Case001_WB
   └─ Case001_WB#2_20260717_143025
      ├─ Case001_WB#2.mp4
      ├─ Case001_WB#2_<元名>.png
      ├─ Case001_WB#2_<元名>.log
      └─ Case001_WB#2_<元名>.asc
```

## フォールバック命名

Repeat正常：

```text
CaseUnknown_UNKNOWN
└─ CaseUnknown_UNKNOWN#2_20260717_143025
   ├─ CaseUnknown_UNKNOWN#2.mp4
   └─ CaseUnknown_UNKNOWN#2_<元名>.<ext>
```

Repeat不正：

```text
CaseUnknown_UNKNOWN
└─ CaseUnknown_UNKNOWN#Unknown_20260717_143025
   ├─ CaseUnknown_UNKNOWN#Unknown.mp4
   └─ CaseUnknown_UNKNOWN#Unknown_<元名>.<ext>
```

## 開始・停止一致判定

- `video_session.marker`のCaseNoは数値比較。
- Tagは大文字正規化後に比較。
- 不一致なら、有効な開始マーカー時刻でファイルを検索するが、STOP側Case名を使わず`CaseUnknown_UNKNOWN`へ保存し、終了コード1。
- `log_session.marker`と`video_session.marker`のSessionId不一致も`CaseUnknown_UNKNOWN`へのフォールバック扱い。両マーカーを不正扱いにし、両系統とも各保存元の最新1件フォールバックを使い、終了コード1。
- Repeatは開始側へ渡していないため、STOP側の値だけを検証する。

## 直前フォルダ退避

同じCase／Tag／Repeatの通常子フォルダのうち、`_OLD_`を含まない最新1件だけを退避してください。

既存：

```text
Case001_WB#2_20260717_100000
Case001_WB#2_20260717_120000
Case001_WB#2_20260717_140000_OLD_20260717_150000
```

新規日時が`20260717_160000`の場合：

```text
Case001_WB#2_20260717_120000
->
Case001_WB#2_20260717_120000_OLD_20260717_160000
```

その後：

```text
Case001_WB#2_20260717_160000
```

要件：

- `_OLD_`を含むフォルダは候補外。
- 古い通常フォルダはそのまま。
- 親フォルダは退避しない。
- 退避先衝突時は`_01`、`_02`を付ける。
- 退避失敗時は新しい子フォルダを作らず、ファイル混在を防ぎ、移動をスキップし、終了コード1。

## 有効マーカー時の選別

MP4は`video_session.marker`：

```text
CreationTimeUtc >= VideoStartTimeUtc
```

- 複数なら最新1件。
- 0件なら警告のみ。最新へフォールバックしない。
- `ObsStartSucceeded=0`ならMP4を移動しない。終了コード1。

PNG／LOG／ASCは`log_session.marker`：

```text
PNG: CreationTimeUtc >= SessionStartTimeUtc
LOG: LastWriteTimeUtc >= LogStartTimeUtc
ASC: LastWriteTimeUtc >= LogStartTimeUtc
```

- 条件一致すべてを対象。
- 0件は警告のみ。

## マーカーなし／破損時

動画マーカーとログマーカーを独立して扱ってください。

- 動画マーカーなし：最新MP4 1件。
- ログマーカーなし：最新PNG、最新LOG、最新ASCを各1件。
- STOP側引数が正常なら正常命名。
- STOP側引数不正ならフォールバック命名。
- マーカー欠落・破損があるため、移動成功でも終了コード1。
- 片方だけ欠落なら、その系統だけ最新1件へフォールバックし、もう片方は有効時刻条件を使う。

## エラー継続

- OBS停止失敗でもTera Term停止と保存処理を続ける。
- フォルダ準備失敗でも停止は完了させる。
- 1ファイル失敗でも他ファイル、他拡張子を続ける。
- 対象0件だけなら0。
- 共通ログファイルを作らない。

## マーカー削除

処理終了時に`log_session.marker`と`video_session.marker`の削除を試行。削除失敗だけなら警告。

## 完了報告

- 新規ファイル全文またはunified diff
- 正常、引数不正、Case不一致、SessionId不一致、片方のマーカー欠落、OBS開始失敗の各フロー
- 直前フォルダ退避例
- 静的確認
- 実機確認項目
- BAT未実行の明記

---

# Step 7：統合静的レビュー用プロンプト

6ファイルの変更を横断レビューしてください。追加実装は、明確な不整合修正だけに限定してください。

対象：

```text
VERI.can
START_REC.bat
START_REC2.bat
START_REC3.bat
STOP_REC.bat
STOP_REC2.bat
```

変更禁止確認：

```text
MM_前進ミラー開_153Cases.txt
obs_record_start.ps1
obs_record_stop.ps1
VERI.cbf
VERIsysvar.vsysvar
```

## 1. 引数契約

| BAT | 期待引数 |
|---|---|
| `START_REC.bat` | CaseNo, Tag |
| `START_REC2.bat` | なし |
| `START_REC3.bat` | CaseNo, Tag |
| `STOP_REC.bat` | CaseNo, Tag |
| `STOP_REC2.bat` | CaseNo, Tag, Repeat |

`VERI.can`の振り分けとBAT側の受取数が完全一致すること。

## 2. マーカー契約

- `legacy_session.marker`
- `log_session.marker`
- `video_session.marker`

キー名、日時形式、SessionId、Case比較、`ObsStartSucceeded`の解釈がSTART／STOP間で一致すること。

## 3. 命名契約

従来正常：

```text
Case001_WB_yyyyMMdd_HHmmss\Case001_WB.mp4
```

従来フォールバック：

```text
yyyyMMdd_HHmmss\yyyyMMdd_HHmmss.mp4
```

新方式正常：

```text
Case001_WB\Case001_WB#2_yyyyMMdd_HHmmss\Case001_WB#2.mp4
```

新方式フォールバック：

```text
CaseUnknown_UNKNOWN\CaseUnknown_UNKNOWN#2_yyyyMMdd_HHmmss\CaseUnknown_UNKNOWN#2.mp4
```

## 4. ファイル選別契約

- MP4：CreationTimeUtc、最新1件。
- PNG：CreationTimeUtc。
- LOG／ASC：LastWriteTimeUtc。
- 有効マーカー時は開始時刻以降。
- 有効マーカーあり・対象なしは最新へフォールバックしない。
- マーカーなしは各種類の最新1件。
- OBS開始失敗時はMP4を移動しない。

## 5. 処理継続契約

- START系はOBS失敗でも独立処理を続ける。
- STOP系はCAN、OBS、Tera Termをすべて試行。
- STOP後3秒待ってから保存先準備。
- 保存先失敗時は元ファイルを残す。
- 1件の移動失敗で他を止めない。
- 実エラーは最終的に1、ファイルなしだけなら0。

## 6. タイムアウト

- OBS開始・停止の外側タイムアウトが20秒。
- 子PowerShellがタイムアウト時に残留しない。
- 無期限待機がない。

## 7. 文字コード

- `VERI.can`がCP932／Shift-JIS系。
- `/*@!Encoding:932*/`維持。
- CRLF維持。
- 無関係な全面再フォーマットなし。

## 8. 既知の実行時間優先リスク

将来の新方式テスト定義は次を使います。

```text
START_REC2後 WaitMS 10000
START_REC3後 WaitMS 5000
STOP_REC2後  WaitMS 18000
OBSタイムアウト 20000
```

値を変更しないでください。OBSが異常に遅い場合に処理が重なる可能性を、実機確認項目と残存リスクへ記載してください。

## 9. 報告

- 変更／新規ファイル一覧
- 統合unified diff
- 引数対応表
- マーカー対応表
- 正常／フォールバックの保存例
- 静的確認結果
- 文字コード／改行結果
- CANoeコンパイル必要箇所
- 実機確認手順
- 残存リスク
- BAT／OBS用PowerShell未実行の明記

---

# Step 8：テスト定義は変更せず、将来の記載例だけ確認するプロンプト

`MM_前進ミラー開_153Cases.txt`は変更しないでください。将来、新方式を使う別テスト定義へ記載する例だけを提示してください。

例：

```text
CaseNo    1    WB
Repeat    2    リピート回数
Gaibu     C:\Users\TMC\Desktop\Veri\batfile\START_REC2.bat    ログ開始
WaitMS    10000    ログ開始待機
Gaibu     C:\Users\TMC\Desktop\Veri\batfile\START_REC3.bat    録画開始
WaitMS    5000    録画開始待機
...
Gaibu     C:\Users\TMC\Desktop\Veri\batfile\STOP_REC2.bat     ログ・録画停止
WaitMS    18000    停止・保存待機
```

確認事項：

- `START_REC2`が先、`START_REC3`が後。
- `START_REC2`後は10000ms。
- `START_REC3`後は5000ms。
- `STOP_REC2`後は18000ms。
- Repeatパラメータ1は現在何回目か。
- CaseNoパラメータ2がTag。
- TagはBAT側で大文字化される。
- 現行153ケースファイルへ変更を適用しない。

提示は例示だけとし、ファイルを書き換えないでください。
