# Codex実装依頼：CANoeログ・OBS録画のCaseNo／Tag／Repeat整理（確定仕様版）

## 0. この依頼の扱い

作業ディレクトリにある実ファイルを最初に確認し、既存処理を尊重した最小差分で実装してください。

この依頼文は、作業ディレクトリにある過去の仕様PDFより新しい**確定仕様**です。PDF、既存コメント、過去のプロンプトと矛盾する場合は、必ずこの依頼文を優先してください。

実装前に、対象ファイルの実際の内容、文字コード、改行コード、既存パス、既存待機時間、既存キー操作を確認してください。推測だけで全面書き換えしないでください。

---

## 1. 目的

既存方式と新しい分割方式を共存させ、CANoeテストスクリプト上のCaseNo、Tag、現在のRepeat番号に基づいて、OBS録画、スクリーンショット、Tera Termログ、CANログを安全に整理します。

最優先事項は次の2点です。

1. 取得対象を可能な限り保存すること。
2. 途中の失敗で、CANoeの後続テスト実行を止めないこと。

BATはエラー時に最終的に `exit /b 1` を返して構いません。ただし、CAPL側ではBATの終了コードを理由にテストを中止しません。また、BAT内部では前段の失敗だけを理由に後続の独立処理を省略しないでください。

---

## 2. 変更対象と変更禁止対象

### 2.1 変更するファイル

- `VERI.can`
- `START_REC.bat`
- `STOP_REC.bat`

### 2.2 新規作成するファイル

- `START_REC2.bat`
- `START_REC3.bat`
- `STOP_REC2.bat`

### 2.3 原則として変更しないファイル

- `obs_record_start.ps1`
- `obs_record_stop.ps1`
- `MM_前進ミラー開_153Cases.txt`
- `VERI.cbf`
- `VERIsysvar.vsysvar`

`VERI.cbf` は生成物なので直接編集しないでください。`VERIsysvar.vsysvar` は既存の `VERI::Case1`、`VERI::Case2`、`VERI::RepCNT1` を使用し、新規システム変数を追加しないでください。

`MM_前進ミラー開_153Cases.txt` は仮のテスト定義であり、今回のパッチでは変更しません。現在Tag欄が空の行があっても、そのままにしてください。

追加の共通ヘルパーBAT、PowerShell、実行ファイルを勝手に増やさないでください。各BATと既存PS1だけで実装してください。

---

## 3. 安全上の制約

実環境のOBS、CANoe、Tera Term、録画ファイル、ログファイルへ影響するため、自動環境では次を実行しないでください。

- `START_REC.bat`
- `START_REC2.bat`
- `START_REC3.bat`
- `STOP_REC.bat`
- `STOP_REC2.bat`
- `obs_record_start.ps1`
- `obs_record_stop.ps1`

実施してよいのは、静的確認、差分確認、文字コード確認、改行コード確認、危険なコマンドの目視確認です。CANoeがない環境では `VERI.can` のコンパイルを実施したと偽らず、未実施と明記してください。

---

## 4. 2つの実行方式

## 4.1 従来方式

実行順は次です。

```text
START_REC.bat "1" "WB"
↓
WaitMS 18000
↓
テスト本体
↓
STOP_REC.bat "1" "WB"
↓
WaitMS 18000
```

`START_REC.bat` は従来どおり、OBS録画、CANログ、COM42のTera Termログ、スクリーンショットを開始します。ただし、CaseNo／Tag引数、セッションマーカー、ベストエフォート型エラー処理を追加します。

`STOP_REC.bat` はすべてを停止し、従来に近い日時付き1階層フォルダへ保存します。

## 4.2 新しい分割方式

実行順は次です。

```text
START_REC2.bat
↓
WaitMS 10000
↓
START_REC3.bat "1" "WB"
↓
WaitMS 5000
↓
テスト本体
↓
STOP_REC2.bat "1" "WB" "2"
↓
WaitMS 18000
```

責務は次のとおりです。

| BAT | 引数 | 責務 |
|---|---|---|
| `START_REC2.bat` | なし | CANログ開始、COM42 Tera Termログ開始、スクリーンショット取得 |
| `START_REC3.bat` | CaseNo、Tag | Case親フォルダ作成または再利用、OBS録画開始 |
| `STOP_REC2.bat` | CaseNo、Tag、Repeat | 全停止、子フォルダ準備、直前フォルダ退避、リネーム、移動 |

`START_REC2.bat` と `START_REC3.bat` の順番は、BAT同士の待機ではなくテストスクリプト側の `WaitMS` で保証します。`START_REC3.bat` にREADY待ちを追加しないでください。

上記WaitMSは実行時間優先で確定しています。OBS外側タイムアウトは20秒のため、異常時にはBAT処理と次のテストが重なる可能性があります。この既知のトレードオフを勝手に変更しないでください。

---

## 5. `VERI.can` から渡す引数

GAIBUコマンドで実行するBAT名を判定し、`sysExec()` の第2引数を次のように切り替えてください。

| 実行ファイル | `sysExec()` 第2引数 |
|---|---|
| `START_REC.bat` | `"CaseNo" "Tag"` |
| `START_REC2.bat` | 空文字列 |
| `START_REC3.bat` | `"CaseNo" "Tag"` |
| `STOP_REC.bat` | `"CaseNo" "Tag"` |
| `STOP_REC2.bat` | `"CaseNo" "Tag" "Repeat"` |
| その他の外部コマンド | 空文字列 |

値の取得元は次です。

```text
CASENOのパラメータ1 -> VERI::Case1 -> CaseNo
CASENOのパラメータ2 -> VERI::Case2 -> Tag
REPEATのパラメータ1 -> VERI::RepCNT1 -> 現在のRepeat番号
```

CAPL側で値を検証してBAT呼び出しを抑止してはいけません。空、不正、未設定でも、該当BATへそのまま引用符付きで渡してください。BAT側がフォールバック処理を行います。

例：

```text
START_REC.bat "1" "wb"
START_REC2.bat
START_REC3.bat "1" "wb"
STOP_REC.bat "1" "wb"
STOP_REC2.bat "1" "wb" "2"
```

GAIBU処理を録画専用にせず、その他の外部コマンドは従来どおり動作させてください。

---

## 6. 引数の検証と正規化

検証はBAT側で実施します。

### 6.1 CaseNo

- 1以上の10進整数だけを有効とする。
- `1` と `001` は同じCaseNoとして比較する。
- 表示時は最低3桁でゼロ埋めする。
- 1000以上を切り捨てない。
- `set /a` の8進数解釈に依存しない。

変換例：

```text
1    -> 001
11   -> 011
617  -> 617
1000 -> 1000
```

### 6.2 Repeat

- 1以上の10進整数だけを有効とする。
- 現在何回目かを表す値である。
- 表示時にゼロ埋めしない。

### 6.3 Tag

- 半角英数字、アンダースコア、ハイフンだけを許可する。
- 入力後、`ToUpperInvariant()` 相当で必ず大文字へ正規化する。
- 比較、マーカー、フォルダ名、ファイル名はすべて正規化後のTagを使用する。

例：

```text
wb     -> WB
Wb     -> WB
type-a -> TYPE-A
```

不正な未検証値を、パス、コマンド文字列、PowerShellコードへ直接連結しないでください。

---

## 7. 共通パス

既存環境の次のパスを使用します。

```text
保存先ルート:
C:\Users\TMC\Desktop\LogZips

OBS録画元:
C:\Users\TMC\Videos\Captures

スクリーンショット元:
C:\Users\TMC\Pictures\Screenshots

Tera Termログ元:
C:\teraterm-5.2\log

CANログ元:
C:\Users\TMC\Desktop\LogZips\CANtemp

BAT配置先・マーカー配置先:
%~dp0
```

すべてのパスを二重引用符で囲んでください。ワイルドカードを無条件で `move` せず、対象ファイルを列挙して1件ずつ移動してください。

---

## 8. セッションマーカー仕様

同時に複数セッションは実行しません。マーカーはBAT配置フォルダへ置きます。

```text
%~dp0legacy_session.marker
%~dp0log_session.marker
%~dp0video_session.marker
```

マーカーはASCII互換の `key=value` 形式、1項目1行、CRLFで保存してください。時刻はUTCのISO 8601 round-trip形式、例えば `2026-07-17T05:30:25.1234567Z` を使用してください。

未検証の生引数はマーカーへ書かないでください。有効値は正規化して保存し、空欄または不正な項目は値を空欄にしてください。空欄は正常な省略、不正な非空欄値は `ArgsValid=0` で表します。

## 8.1 `legacy_session.marker`

少なくとも次を記録してください。

```text
Version=2
SessionId=<GUID>
ArgsValid=0|1
CaseNoCanonical=<1以上の正規化数値または空欄>
TagNormalized=<大文字Tagまたは空欄>
SessionStartTimeUtc=<START_REC開始時刻>
VideoStartTimeUtc=<OBS開始呼出し直前時刻>
LogStartTimeUtc=<CANログ開始操作直前時刻>
ObsStartSucceeded=0|1
```

## 8.2 `log_session.marker`

少なくとも次を記録してください。

```text
Version=1
SessionId=<GUID>
SessionStartTimeUtc=<START_REC2開始時刻>
LogStartTimeUtc=<CANログ開始操作直前時刻>
```

## 8.3 `video_session.marker`

少なくとも次を記録してください。

```text
Version=2
SessionId=<log_session.markerから引き継いだGUID、なければ新規GUID>
ArgsValid=0|1
CaseNoCanonical=<1以上の正規化数値または空欄>
TagNormalized=<大文字Tagまたは空欄>
VideoStartTimeUtc=<OBS開始呼出し直前時刻>
ObsStartSucceeded=0|1
```

`START_REC3.bat` は有効な `log_session.marker` があれば、その `SessionId` を引き継いでください。存在しない、読めない場合は新しいGUIDを使用し、エラー状態を保持したままOBS開始を試行してください。

STOP側はVersion 1と2を読み込み、Version 1の `UNKNOWN` は空欄へ読み替えてください。新方式で両マーカーの `SessionId` が一致しない場合はCaseNoとTagを命名に使用せず、有効なRepeatと日時だけで保存してください。両マーカーの時刻も信頼せず、両系統を後述の「マーカーなし／不正時」と同じ最新1件フォールバックで処理し、最終終了コードを1にしてください。

START系は既存マーカーを上書きします。STOP系は、成功、警告、エラー、移動失敗にかかわらず、最後に対応マーカーを削除してください。削除失敗は警告表示のみとし、別の共通ログファイルは作成しません。

OBS開始前に `ObsStartSucceeded=0` でマーカーを書き、OBS開始成功後に `1` へ更新してください。OBS開始失敗時もマーカーを残し、STOP側へ失敗情報を引き継いでください。

---

## 9. `START_REC.bat` の確定仕様

入力：

```text
%1 = CaseNo（省略可）
%2 = Tag（省略可）
```

既存の操作順と既存パスを維持し、次の順で実装してください。

```text
引数取得・検証・Tag大文字化
↓
legacy_session.marker作成
↓
OBS録画開始を試行
↓
CANログ開始を試行
↓
COM42 Tera Termログ開始を試行
↓
スクリーンショット取得を試行
↓
最終結果表示
↓
exit /b 0 または 1
```

要件：

- 空欄は正常な省略とし、不正な非空欄値があっても取得処理を中止しない。
- OBS開始失敗でもCAN、Tera Term、スクリーンショットを続行する。
- 既存のMeasurement Setup、COM42、キー操作、待機、スクリーンショット操作を維持する。
- COM39の到達不能な既存コードなど、無関係な部分を整理しない。
- OBS開始は既存 `obs_record_start.ps1` を使用する。
- OBS開始に20秒の外側タイムアウトを設ける。
- タイムアウト時は、このBATが起動した対象PowerShellプロセスだけを終了し、後続を続ける。
- 引数不正、マーカー書込み失敗、OBS失敗、その他の実行失敗が1件でもあれば、すべての処理後に `exit /b 1`。
- 警告だけなら `exit /b 0`。

---

## 10. `START_REC2.bat` の確定仕様

引数はありません。CaseNo、Tag、Repeatを渡さないでください。

処理順：

```text
log_session.marker作成
↓
CANログ開始を試行
↓
COM42 Tera Termログ開始を試行
↓
スクリーンショット取得を試行
↓
最終結果表示
↓
exit /b 0 または 1
```

要件：

- 既存 `START_REC.bat` のCANログ開始、COM42 Tera Termログ開始、スクリーンショット部分を参照する。
- OBSへ一切触れない。
- フォルダ作成、Repeat子フォルダ作成、ファイル移動を行わない。
- 前段が失敗しても次の処理を続ける。
- マーカー作成や操作失敗があれば最後に `exit /b 1`。

---

## 11. `START_REC3.bat` の確定仕様

入力：

```text
%1 = CaseNo（省略可）
%2 = Tag（省略可）
```

正常時の親フォルダ：

```text
C:\Users\TMC\Desktop\LogZips\Case001_WB
```

処理順：

```text
引数取得・検証・Tag大文字化
↓
有効なCaseNoまたはTagがあれば、その項目だけで親フォルダ作成または再利用を試行。両方空欄ならLogZips直下を使用
↓
video_session.marker作成
↓
OBS録画開始を試行
↓
最終結果表示
↓
exit /b 0 または 1
```

要件：

- 親フォルダが存在する場合、削除、退避、初期化せず、そのまま再利用する。
- CaseNoとTagが両方空欄なら専用親フォルダを作らず、`LogZips` 直下を使用する。不正な項目は親フォルダ名に使用しない。
- 引数不正または親フォルダ作成失敗でもOBS録画開始を試行する。
- CANログ、Tera Term、スクリーンショット、Repeat子フォルダ作成、ファイル移動を行わない。
- 既存 `obs_record_start.ps1` を使用し、20秒の外側タイムアウトを設ける。
- タイムアウト時は、このBATが起動した対象PowerShellプロセスだけを終了する。
- 引数不正、親フォルダ作成失敗、マーカー異常、OBS開始失敗があれば、最後に `exit /b 1`。

---

## 12. STOP系BATの共通処理順

`STOP_REC.bat` と `STOP_REC2.bat` は、必ず次の大順序で処理してください。

```text
引数・マーカー読込み
↓
STOP開始日時DTを1回だけ取得
↓
CANログ停止を試行
↓
OBS録画停止を試行
↓
COM42 Tera Termログ停止を試行
↓
3秒待機
↓
保存先準備
↓
必要なら既存フォルダ退避
↓
ファイル検索・リネーム・移動
↓
マーカー削除
↓
最終結果表示
↓
exit /b 0 または 1
```

日時 `DT` はPowerShellのローカル日時で、ロケール非依存の次形式を使用してください。

```text
yyyyMMdd_HHmmss
```

同じDTを保存先名、OLD退避名、フォールバック名へ使用してください。

停止処理の途中で失敗しても、残りの停止処理をすべて試行してください。保存先作成や退避が失敗しても、すでに停止処理は完了させ、ファイルは元の場所へ残してください。

OBS停止は既存 `obs_record_stop.ps1` を使用し、20秒の外側タイムアウトを設けてください。タイムアウト時もTera Term停止とファイル整理を続けてください。

---

## 13. `STOP_REC.bat` の確定仕様

入力：

```text
%1 = CaseNo
%2 = Tag
```

### 13.1 正常時の保存先と命名

CaseNo=`1`、Tag=`wb`、DT=`20260717_143025` の場合：

```text
C:\Users\TMC\Desktop\LogZips
└─ Case001_WB_20260717_143025
   ├─ Case001_WB.mp4
   ├─ Case001_WB_<元ファイル名>.png
   ├─ Case001_WB_<元ファイル名>.log
   └─ Case001_WB_<元ファイル名>.asc
```

```text
フォルダ名 = Case{最低3桁CaseNo}_{大文字Tag}_{DT}
ファイル接頭辞 = Case{最低3桁CaseNo}_{大文字Tag}
```

### 13.2 フォールバック

CaseNoとTagが両方空欄、STARTとSTOPのCaseNo／Tagが不一致、または命名に使用できる項目がない場合：

```text
C:\Users\TMC\Desktop\LogZips
└─ 20260717_143025
   ├─ 20260717_143025.mp4
   ├─ 20260717_143025_<元ファイル名>.png
   ├─ 20260717_143025_<元ファイル名>.log
   └─ 20260717_143025_<元ファイル名>.asc
```

開始・停止不一致時は、停止操作をすべて実行し、開始マーカーの時刻で今回分を検索しますが、STOP側のCase名では保存しません。警告を表示し、最終終了コードを1にしてください。

CaseNoまたはTagの一方だけが空欄なら、有効な一方だけを保存先名とファイル名に使用してください。マーカーが存在しない、または読めない場合も、STOP側の有効な項目だけを命名に使用し、各保存元の最新1件へフォールバックしてください。マーカー欠落自体はエラーなので、最終終了コードを1にしてください。

同じ秒の完全同名保存先がすでに存在する場合、新旧ファイルを混在させないでください。既存フォルダへ追加せず、保存先準備失敗として移動を中止し、最終終了コードを1にしてください。

---

## 14. `STOP_REC2.bat` の確定仕様

入力：

```text
%1 = CaseNo（省略可）
%2 = Tag（省略可）
%3 = 現在のRepeat番号（省略可）
```

### 14.1 保存先と命名

CaseNo=`1`、Tag=`wb`、Repeat=`2`、DT=`20260717_143025` の場合：

```text
C:\Users\TMC\Desktop\LogZips
└─ Case001_WB
   └─ Case001_WB#2_20260717_143025
      ├─ Case001_WB#2.mp4
      ├─ Case001_WB#2_<元ファイル名>.png
      ├─ Case001_WB#2_<元ファイル名>.log
      └─ Case001_WB#2_<元ファイル名>.asc
```

```text
親フォルダ = 有効なCaseNoとTagだけを `_` で連結。両方空欄ならLogZips直下
子フォルダ = 有効なCaseNo、Tag、Repeatから作った命名部品 + `_` + DT
ファイル接頭辞 = 有効なCaseNo、Tag、Repeatから作った命名部品
```

親フォルダがない場合はSTOP側で作成し、警告を表示してください。作成できれば処理を続け、作成できなければ移動を中止して最終終了コードを1にしてください。

### 14.2 空欄項目とフォールバック

空欄項目は正常な省略として、入力されている有効項目だけで命名してください。余分な `_` や `#` は付けません。

| 入力 | 命名部品 | 子フォルダ |
|---|---|---|
| Case、Tag、Repeat | `Case001_TAG#2` | `Case001_TAG#2_20260717_143025` |
| Case、Tag | `Case001_TAG` | `Case001_TAG_20260717_143025` |
| Case、Repeat | `Case001#2` | `Case001#2_20260717_143025` |
| Tag、Repeat | `TAG#2` | `TAG#2_20260717_143025` |
| Caseのみ | `Case001` | `Case001_20260717_143025` |
| Tagのみ | `TAG` | `TAG_20260717_143025` |
| Repeatのみ | `Repeat2` | `Repeat2_20260717_143025` |
| すべて空欄 | 日時 | `20260717_143025` |

開始・停止不一致またはSessionId不一致時は、停止操作をすべて実行し、CaseNoとTagを命名から除外してください。有効なRepeatがあれば `Repeat2_<DT>`、なければ `<DT>` とし、最終終了コードを1にしてください。

マーカーが存在しない、または読めない場合は、STOP側の有効なCaseNo、Tag、Repeatだけを命名に使用します。対象ファイルは各保存元の最新1件へフォールバックし、最終終了コードを1にしてください。

---

## 15. 新方式の直前フォルダ退避

`STOP_REC2.bat` は新しい子フォルダを作る前に、同じCaseNo、Tag、Repeatに該当する通常フォルダのうち、最新の1件だけを退避してください。

例：

```text
Case001_WB#2_20260717_100000
Case001_WB#2_20260717_120000
Case001_WB#2_20260717_140000_OLD_20260717_150000
```

新規DT=`20260717_160000` の場合、`_OLD_` を含まない通常フォルダのうち最新の次だけを退避します。

```text
Case001_WB#2_20260717_120000
↓
Case001_WB#2_20260717_120000_OLD_20260717_160000
```

その後、次を作成します。

```text
Case001_WB#2_20260717_160000
```

要件：

- `_OLD_` を含むフォルダは検索対象から除外する。
- 古い通常フォルダはそのまま残す。
- 親フォルダは退避しない。
- 退避先が同名なら `_01`、`_02` のような連番を追加する。
- 退避失敗時は新しい子フォルダを作らず、ファイルを移動せず、最終終了コードを1にする。
- CaseNoとTagが両方ない場合は `LogZips` 直下の同じ命名部品に完全一致する子フォルダだけを対象にする。全項目空欄では日時形式だけを対象にする。

---

## 16. ファイル選択規則

## 16.1 有効なマーカーがある場合

| 種類 | 判定時刻 | 対象 |
|---|---|---|
| MP4 | `CreationTimeUtc >= VideoStartTimeUtc` | 条件一致中、CreationTimeUtcが最新の1件 |
| PNG | `CreationTimeUtc >= SessionStartTimeUtc` | 条件一致する全件 |
| LOG | `LastWriteTimeUtc >= LogStartTimeUtc` | 条件一致する全件 |
| ASC | `LastWriteTimeUtc >= LogStartTimeUtc` | 条件一致する全件 |

従来方式では `legacy_session.marker` を使用します。新方式では、MP4に `video_session.marker`、PNG／LOG／ASCに `log_session.marker` を使用します。

MP4候補が複数ある場合は警告を表示し、最新の1件だけを使用してください。他のMP4は元の場所へ残します。複数候補自体は警告であり、それだけでは終了コードを1にしません。

有効なマーカーがあるのに時刻条件へ一致するファイルが0件の場合、単純な最新ファイルへフォールバックしないでください。「今回その種類のファイルが生成されなかった」と扱い、警告だけ表示します。他にエラーがなければ終了コードは0です。

## 16.2 マーカーがない、読めない、必須キーがない場合

対応する保存元から、各種類につき最新の1件だけを取得してください。

| 種類 | 最新判定 |
|---|---|
| MP4 | `CreationTimeUtc` が最新の1件 |
| PNG | `CreationTimeUtc` が最新の1件 |
| LOG | `LastWriteTimeUtc` が最新の1件 |
| ASC | `LastWriteTimeUtc` が最新の1件 |

マーカー欠落または不正はエラーとして保持し、ファイル移動に成功しても最終終了コードを1にしてください。

新方式で片方のマーカーだけが正常な場合は、正常なマーカーを対応ファイル種別に使用し、異常な側だけ最新1件フォールバックへ進めてください。両マーカーのSessionId不一致時は両方を不正扱いにし、CaseNoとTagを命名から除外してください。

## 16.3 OBS開始失敗時

マーカーに `ObsStartSucceeded=0` が記録されている場合：

- OBS停止操作自体は試行する。
- MP4を移動しない。
- 最新MP4へフォールバックしない。
- PNG、LOG、ASCはそれぞれの通常規則で処理する。
- OBS開始失敗をエラーとして保持し、STOP側も最終終了コードを1にする。

## 16.4 開始・停止Case照合

有効な開始マーカーがある場合、開始時と停止時のCaseNo、Tagを正規化後に比較してください。

```text
CaseNo 1 == 001
Tag WB == wb  （大文字化後）
```

不一致時も開始マーカーの時刻はファイル選択に使用します。ただしCaseNoとTagは命名に使用せず、従来方式は日時だけ、新方式は有効なRepeatと日時だけで保存します。

---

## 17. リネーム規則

### 17.1 従来方式

正常時の接頭辞：

```text
Case001_WB
```

CaseNoとTagを使用できず、Repeatだけが有効な場合の接頭辞：

```text
20260717_143025
```

### 17.2 新方式

正常時の接頭辞：

```text
Case001_WB#2
```

フォールバック時の接頭辞：

```text
Repeat2
```

全項目を使用できない場合：

```text
20260717_143025
```

### 17.3 各ファイル

MP4：

```text
<接頭辞>.mp4
```

PNG／LOG／ASC：

```text
<接頭辞>_<元ファイル名>
```

元ファイル名には元の拡張子を含めてください。ファイルは1件ずつ処理し、存在するファイルの移動やリネームに失敗しても、他ファイルの処理を続けてください。

---

## 18. エラー、警告、終了コード

全BATで内部的にエラー有無を保持し、最後に1回だけ終了コードを決定してください。メイン処理途中での早期 `exit /b 1` は禁止です。

### 18.1 `exit /b 1` にする例

- 引数不正
- マーカー作成、読込み、必須キー解析失敗
- マーカー欠落
- 新方式のSessionId不一致
- 開始・停止CaseNo／Tag不一致
- OBS開始失敗、OBS停止失敗、20秒タイムアウト
- 親または子フォルダ作成失敗
- 既存フォルダ退避失敗
- 存在する対象ファイルの移動・リネーム失敗

### 18.2 警告だけで `exit /b 0` にできる例

- 有効なマーカーがあり、今回分のMP4／PNG／LOG／ASCが存在しない
- MP4候補が複数あり、最新1件を選択した
- START_REC3で親フォルダが既に存在し再利用した
- STOP_REC2で親フォルダがなく、STOP側で作成できた
- マーカー削除失敗

ただし、同じ実行内に別のエラーがあれば最終終了コードは1です。

`STRICT_EXIT` のようなモード切替は実装しないでください。通常時から上記ルールで0または1を返します。

CAPL側はBATのエラーコードを理由にテストを止めません。

---

## 19. OBS外側タイムアウト

`obs_record_start.ps1` と `obs_record_stop.ps1` 自体は原則変更せず、BAT側から20秒の外側タイムアウトを実装してください。

要件：

- 対象PowerShellを子プロセスとして起動し、最大20秒待つ。
- 20秒以内に終了した場合は、その終了コードを取得する。
- タイムアウト時は、そのBATが起動したPowerShellプロセスだけを終了する。
- 他のPowerShellプロセスを名前だけで一括終了しない。
- タイムアウト後も後続処理を続ける。

---

## 20. 画面ログ

ファイルへの共通エラーログは作成しません。BAT画面とCANoe Writeウィンドウだけへ出力します。

BATは主要処理ごとに、少なくとも次を表示してください。

```text
[INFO] Raw/normalized arguments
[INFO] Marker path and marker status
[INFO] SessionId and relevant UTC timestamps
[INFO] OBS start/stop result
[INFO] Destination folder
[INFO] Archived OLD folder
[INFO] Selected source file
[INFO] Renamed destination file
[WARN] Missing file or multiple MP4 candidates
[ERROR] Failed operation
[RESULT] success/warning/error summary and exit code
```

未検証引数をそのまま `echo` してコマンドとして解釈させないよう注意してください。

`VERI.can` のWriteウィンドウには、外部コマンドパスと実際に渡す引数の両方を表示してください。引数なしの場合も分かる表示にしてください。

---

## 21. `VERI.can` の実装要件

既存のCASENO、REPEAT処理とシステム変数設定を維持してください。

```text
VERI::Case1
VERI::Case2
VERI::RepCNT1
```

GAIBU処理だけを必要最小限拡張し、実行ファイル名に応じて第2引数を切り替えてください。

実装上の要件：

- フルパスからBAT名を安全に判定する。
- 大文字・小文字の差で判定に失敗しない。
- `START_REC.bat.bak` などを誤判定しない。
- 引数は必ず二重引用符付きで作成する。
- 固定長バッファを超えない。
- `snprintf()` などの使用可否を現行CAPL環境に合わせる。未対応なら既存環境で利用可能な安全な文字列関数を使用する。
- 値が空でも `""` として渡す。
- `sysExec()` 呼出し後に終了コード待ちやテスト中止処理を追加しない。
- その他のGAIBUコマンドは空引数のまま。
- `/*@!Encoding:932*/`、CP932／Shift-JIS系、CRLFを維持する。
- ファイル全体をUTF-8化、再フォーマットしない。

想定ログ例：

```text
commandline:C:\Users\TMC\Desktop\Veri\batfile\STOP_REC2.bat args:"1" "WB" "2"
```

---

## 22. 変更禁止事項

- OBSの録画設定や録画ファイル名フォーマットを変更しない。
- `obs_record_start.ps1` にCaseNoを渡してOBS側でファイル名を変更しない。
- `obs_record_stop.ps1` 内で移動、リネーム、アーカイブを行わない。
- Captures内の全MP4を無条件で移動しない。
- PNG、LOG、ASCを無条件のワイルドカードmoveで全移動しない。
- テスト定義153ケースへTagやBAT行を一括追記しない。
- `MM_前進ミラー開_153Cases.txt` を変更しない。
- `VERI.cbf` を直接変更しない。
- `VERIsysvar.vsysvar` に新規変数を追加しない。
- 関係のないCAPL処理、コメント、COM39到達不能コードをリファクタリングしない。
- `pause`、確認ダイアログ、ユーザー入力待ち、無期限待機を追加しない。
- エラー時にSTOP系の後続処理を途中終了しない。
- `STRICT_EXIT` を追加しない。
- 共通エラーログファイルを作成しない。

---

## 23. 静的受け入れ条件

最低限、次を確認してください。

### 23.1 引数連携

- `START_REC.bat` は2引数。
- `START_REC2.bat` は引数なし。
- `START_REC3.bat` は2引数。
- `STOP_REC.bat` は2引数。
- `STOP_REC2.bat` は3引数。
- その他GAIBUは引数なし。

### 23.2 正常系命名

CaseNo=`1`、Tag=`wb`：

```text
Case001_WB_yyyyMMdd_HHmmss\Case001_WB.mp4
```

CaseNo=`1`、Tag=`wb`、Repeat=`2`：

```text
Case001_WB\Case001_WB#2_yyyyMMdd_HHmmss\Case001_WB#2.mp4
```

### 23.3 変換

```text
CaseNo 1    -> 001
CaseNo 11   -> 011
CaseNo 617  -> 617
CaseNo 1000 -> 1000
Tag wb      -> WB
Repeat 2    -> 2
```

### 23.4 フォールバック

- 従来方式の引数不正または開始停止不一致は日時だけのフォルダ。
- 新方式の空欄は省略し、不正な項目は除外する。開始停止不一致ではCaseNoとTagを除外し、有効なRepeatと日時だけを使用する。
- Repeatだけ有効ならそのRepeatをフォールバック名へ残す。
- マーカー欠落時はSTOP側の有効引数を命名へ使い、各種類の最新1件を処理し、終了コード1。

### 23.5 ファイル選択

- 有効マーカー時、開始前から存在したファイルを移動しない。
- 有効マーカー時、対象0件なら最新ファイルへフォールバックしない。
- MP4複数時は最新1件だけ。
- PNG／LOG／ASCは有効マーカーの時刻条件に合う全件。
- マーカー欠落時は各種類の最新1件だけ。
- `ObsStartSucceeded=0` ならMP4を移動しない。

### 23.6 継続性

- OBS開始失敗後もSTART_RECはCAN、Tera Term、スクリーンショットを試行する。
- OBS停止失敗後もSTOP系はTera Term停止、保存先準備、移動を試行する。
- 1件の移動失敗で他ファイルを止めない。
- STOP系に途中の `exit /b 1` がない。

### 23.7 フォルダ退避

- 新方式で同じCase／Tag／Repeatの通常フォルダの最新1件だけをOLD退避する。
- `_OLD_` を含むフォルダを再退避しない。
- 退避失敗時に新旧ファイルを混在させない。

### 23.8 非変更確認

- `MM_前進ミラー開_153Cases.txt` 未変更。
- `VERI.cbf` 未変更。
- `VERIsysvar.vsysvar` 未変更。
- `obs_record_start.ps1` と `obs_record_stop.ps1` は原則未変更。
- `VERI.can` のCP932系エンコーディングとCRLFを維持。
- BATも既存と整合する文字コードとCRLFを維持。

---

## 24. 実機確認項目

自動環境では実行せず、作業完了報告へ次の実機確認項目を列挙してください。

1. CANoeで `VERI.can` がコンパイルできる。
2. WriteウィンドウのBAT別引数が正しい。
3. 従来方式の正常保存とリネーム。
4. 新方式の正常保存とリネーム。
5. Tag小文字入力が大文字化される。
6. CaseNo=`1` と `001` が一致扱いになる。
7. 開始停止不一致時のフォールバック。
8. マーカー削除時の最新1件フォールバック。
9. 有効マーカーで対象0件のとき古いファイルを動かさない。
10. OBS開始失敗時にMP4を動かさず他ログを処理する。
11. OBS停止20秒タイムアウト後も後続が進む。
12. 新方式の最新1件OLD退避。
13. 移動失敗時に他種類が継続する。
14. BATが1を返してもCANoeの次テストが進む。

---

## 25. 作業完了時の報告

次を提示してください。

1. 変更・新規作成したファイル一覧
2. 各ファイルの変更概要
3. unified diff
4. 実施した静的確認と結果
5. 文字コード・CRLF確認結果
6. CANoeコンパイル未実施または実施結果
7. 実機確認が必要な項目
8. 残る既知のリスク

既知のリスクとして、少なくとも次を明記してください。

- `START_REC3` 後のWaitMS 5000はOBS外側タイムアウト20秒より短い。
- `STOP_REC2` 後のWaitMS 18000は異常時の全処理時間より短い可能性がある。
- マーカー欠落時は、仕様どおり各保存元の最新ファイルをSTOP側Case名で保存するため、古いファイル誤関連付けのリスクが残る。

元の処理を大きく書き換えず、差分を小さく保ってください。
