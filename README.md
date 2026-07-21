# AutoVisualCheck BAT運用ガイド

## 1. このプロジェクトの目的

このプロジェクトは、CANoeでテストを実行しながら、次の証跡を取得して `C:\Users\TMC\Desktop\LogZips` 配下へまとめるためのものです。

- OBSの録画（MP4）
- Windowsのスクリーンショット（PNG）
- COM42のTera Termログ（LOG）
- CANログ（ASC）

録画・ログ取得には、従来方式と新方式の2種類があります。1回のテストで両方式を混在させず、いずれか一方の組み合わせを使用してください。

| 方式 | 実行順 | 主な違い |
| --- | --- | --- |
| 従来方式 | `START_REC.bat` → テスト本体 → `STOP_REC.bat` | 録画、ログ、スクリーンショットを1つのSTARTで開始し、1つの保存フォルダへ格納する |
| 新方式 | `START_REC2.bat` → `START_REC3.bat` → テスト本体 → `STOP_REC2.bat` | ログ開始と録画開始を分離し、Case/Tagの親フォルダの下へRepeat別に保存する。前回フォルダの退避機能がある |

> 本書はリポジトリ内のBAT、PowerShell、CAPLを静的に確認して作成しています。OBS、CANoe、Tera Termを接続した実機動作確認は行っていません。

## 2. 実行前の前提

BATは次の配置を前提に、固定パスで外部ツールや保存先を参照します。

```text
C:\Users\TMC\Desktop\Veri\batfile
```

実行前に、少なくとも次を確認してください。

- OBSが起動し、OBS WebSocketを `ws://127.0.0.1:4455` で利用できること
- CANoeの対象ウィンドウ名が `Measurement Setup` であること
- Tera Termの対象ウィンドウ名が `COM42 - Tera Term VT` であること
- `nircmd.exe`、`obs_record_start.ps1`、`obs_record_stop.ps1` がBATと同じ運用フォルダにあること
- 次の移動元・保存先へアクセスできること

手動実行する場合は、コマンドプロンプトで次のように運用フォルダへ移動します。

```bat
cd /d C:\Users\TMC\Desktop\Veri\batfile
```

## 3. 引数の共通ルール

| 引数 | 使用BAT | 形式と正規化 |
| --- | --- | --- |
| `CaseNo` | `START_REC.bat`、`STOP_REC.bat`、`START_REC3.bat`、`STOP_REC2.bat` | 1文字以上の数字。先頭の0を除いて管理し、保存名では3桁以上になるよう左側を0埋めする。`0` や数字以外は無効 |
| `Tag` | 同上 | 英字、数字、`_`、`-` のみ。保存名と比較時は大文字へ正規化する。空文字は無効 |
| `Repeat` | `STOP_REC2.bat`のみ | 1文字以上の数字。先頭の0を除いて管理する。`0` や数字以外は無効 |

例: `CaseNo=1`、`Tag=mm-a`、`Repeat=01` は、保存名ではそれぞれ `001`、`MM-A`、`1` になります。

STARTとSTOPには同じ `CaseNo` と `Tag` を渡してください。新方式では、`START_REC2.bat` に引数はありません。

## 4. 従来方式の使い方

### 実行順

```text
START_REC.bat CaseNo Tag
  ↓
テスト本体
  ↓
STOP_REC.bat CaseNo Tag
```

手動実行例（CaseNo `1`、Tag `MM`）:

```bat
call START_REC.bat 1 MM
rem ここでテスト本体を実行
call STOP_REC.bat 1 MM
```

### `START_REC.bat` の役割

`START_REC.bat CaseNo Tag` は、次を順番に実行します。

1. `legacy_session.marker` を作成し、CaseNo、Tag、セッションID、開始時刻を記録する
2. `obs_record_start.ps1` を呼び出してOBS録画を開始する
3. `Measurement Setup` をアクティブにし、`t` キーでCANログを開始する
4. `COM42 - Tera Term VT` を操作し、Tera Termログを開始する
5. `rwin+printscreen` を送信してスクリーンショットを取得する

OBS開始処理は最大20秒待ちます。処理が失敗しても後続のCANログ、Tera Termログ、スクリーンショット処理を続け、最後にエラー終了します。

### `STOP_REC.bat` の役割

`STOP_REC.bat CaseNo Tag` は、次を順番に実行します。

1. 引数と `legacy_session.marker` を検証する
2. CANログを停止する
3. `obs_record_stop.ps1` を呼び出してOBS録画を停止する
4. COM42のTera Termログを停止する
5. 保存フォルダを作成し、MP4、PNG、LOG、ASCを移動する
6. `legacy_session.marker` を削除する

マーカーが有効な場合は、各開始時刻以降のファイルを選びます。MP4が複数ある場合は最新の1件、PNG・LOG・ASCは条件に一致した全件が対象です。マーカーがない、または無効な場合は、各種類の最新1件を選ぶフォールバック動作になります。

保存先は次の形式です。

```text
C:\Users\TMC\Desktop\LogZips\Case{CaseNoを3桁以上に0埋め}_{大文字Tag}_{yyyyMMdd_HHmmss}
```

例:

```text
C:\Users\TMC\Desktop\LogZips\Case001_MM_20260721_143000
```

引数が無効、STARTとSTOPのCaseNo/Tagが不一致、または有効なSTARTマーカー内の引数が無効な場合は、日時だけのフォールバック名を使用します。

```text
C:\Users\TMC\Desktop\LogZips\20260721_143000
```

ただし、マーカーがない場合でもSTOPの引数が有効なら、通常の `Case001_MM_...` 形式を使用します。

## 5. 新方式の使い方

### 実行順

```text
START_REC2.bat
  ↓
START_REC3.bat CaseNo Tag
  ↓
テスト本体
  ↓
STOP_REC2.bat CaseNo Tag Repeat
```

手動実行例（CaseNo `1`、Tag `MM`、Repeat `1`）:

```bat
call START_REC2.bat
call START_REC3.bat 1 MM
rem ここでテスト本体を実行
call STOP_REC2.bat 1 MM 1
```

### `START_REC2.bat` の役割

`START_REC2.bat` は引数を取りません。ログ側の開始処理を担当します。

1. 前回の `log_session.marker` と `video_session.marker` を無効化する
2. 新しいセッションIDとセッション開始時刻を `log_session.marker` に記録する
3. CANログ開始時刻をマーカーへ記録し、`Measurement Setup` へ `t` キーを送ってCANログを開始する
4. COM42のTera Termログを開始する
5. スクリーンショットを取得する

このBATはOBS録画を開始しません。

### `START_REC3.bat` の役割

`START_REC3.bat CaseNo Tag` は録画側の開始処理を担当します。

1. 前回の `video_session.marker` を無効化する
2. 引数が有効なら `C:\Users\TMC\Desktop\LogZips\Case{CaseNo}_{Tag}` 親フォルダを作成または再利用する
3. `log_session.marker` からセッションIDを引き継ぐ
4. 録画開始時刻とCaseNo/Tagを `video_session.marker` に記録する
5. OBS録画を開始し、成功結果を同マーカーへ記録する

有効な `log_session.marker` を読めない場合は、エラーを記録したうえで代替セッションIDを作り、OBS開始処理まで続行します。この場合、STOP時にログ側と録画側のセッション不一致として扱われる可能性があります。

### `STOP_REC2.bat` の役割

`STOP_REC2.bat CaseNo Tag Repeat` は、次を実行します。

1. 引数、`log_session.marker`、`video_session.marker` を個別に検証する
2. 両マーカーが有効ならセッションIDが一致するか検証する
3. CANログ、OBS録画、COM42のTera Termログを停止する
4. 同じCaseNo/Tag/Repeatの前回フォルダを必要に応じて `_OLD_` 付きへ退避する
5. 新しい子フォルダを作り、MP4、PNG、LOG、ASCを移動する
6. 2つのマーカーを削除する

ログ側と録画側のマーカーを個別に扱うため、一方だけが有効な場合は、有効な側では開始時刻を使い、無効な側では最新1件を選ぶフォールバックを使用します。両マーカーのセッションIDが不一致の場合は両方の時刻情報を破棄し、両側とも最新1件を選びます。

## 6. 保存先フォルダとファイル名

### 新方式の通常構造

```text
C:\Users\TMC\Desktop\LogZips\
└─ Case001_MM\
   └─ Case001_MM#1_20260721_143000\
      ├─ Case001_MM#1.mp4
      ├─ Case001_MM#1_{元のPNGファイル名}
      ├─ Case001_MM#1_{元のLOGファイル名}
      └─ Case001_MM#1_{元のASCファイル名}
```

- 親フォルダ: `Case{CaseNoを3桁以上に0埋め}_{大文字Tag}`
- 子フォルダ: `Case{CaseNo}_{Tag}#{Repeat}_{yyyyMMdd_HHmmss}`
- 日時: `STOP_REC.bat` または `STOP_REC2.bat` を実行したPCのローカル日時
- MP4名: `Case{CaseNo}_{Tag}#{Repeat}.mp4`
- PNG、LOG、ASC名: `Case{CaseNo}_{Tag}#{Repeat}_{移動元ファイル名}`

引数不正やCaseNo/Tag不一致などで通常名を使用できない場合、新方式は次へ保存します。

```text
C:\Users\TMC\Desktop\LogZips\CaseUnknown_UNKNOWN\CaseUnknown_UNKNOWN#1_20260721_143000
```

Repeatも無効な場合は `#Unknown` になります。

### 新方式の退避フォルダ

新しい子フォルダを作る前に、同じ親フォルダ内から、同じCaseNo/Tag/Repeatに一致する最新の通常子フォルダ1件を探します。見つかった場合は次の形式へ名前を変更します。

```text
Case001_MM#1_20260721_130000_OLD_20260721_143000
```

退避先名がすでに存在する場合は、末尾に `_01`、`_02` のような連番を付けます。名前変更に失敗した場合、新しい子フォルダの作成とファイル移動は行いません。すでに `_OLD_` を含むフォルダは退避対象外です。

従来方式にはこの退避処理はありません。STOP日時まで同じ保存先フォルダがすでに存在する場合はエラーとなり、ファイル移動を行いません。

## 7. 移動元のパス一覧

| 種類 | 移動元 | 通常時の選択基準 |
| --- | --- | --- |
| MP4 | `C:\Users\TMC\Videos\Captures` | 録画開始時刻以降に作成されたMP4のうち最新1件 |
| PNG | `C:\Users\TMC\Pictures\Screenshots` | セッション開始時刻以降に作成されたPNG全件 |
| LOG | `C:\teraterm-5.2\log` | ログ開始時刻以降に更新されたLOG全件 |
| ASC | `C:\Users\TMC\Desktop\LogZips\CANtemp` | ログ開始時刻以降に更新されたASC全件 |

ファイルはコピーではなく移動されます。マーカー時刻を利用できない種類では、その種類の最新1件だけを選びます。1件ずつ移動するため、あるファイルの移動失敗後も、同じ種類の残りのファイルや後続種類の処理を続けます。

## 8. CANoeの `GAIBU` 呼び出し

`VERI\CAPL\VERI.can` の `GAIBU` は外部BATを `C:\Users\TMC\Desktop\Veri\batfile` を作業フォルダとして起動します。BAT名に応じて、CANoeのシステム変数から次の引数を組み立てます。

| BAT | GAIBUから渡される引数 |
| --- | --- |
| `START_REC.bat` | `CaseNo Tag` |
| `STOP_REC.bat` | `CaseNo Tag` |
| `START_REC2.bat` | 引数なし |
| `START_REC3.bat` | `CaseNo Tag` |
| `STOP_REC2.bat` | `CaseNo Tag Repeat` |

`CaseNo` と `Tag` はテスト定義の `CaseNo` 行の第1・第2パラメータ、`Repeat` は `Repeat` 行の第1パラメータから保持されます。新方式へ切り替える場合は、テスト定義側のGAIBU呼び出しも、3つの新方式BATの順序に合わせる必要があります。

現在の `MM_前進ミラー開_153Cases.txt` は、従来方式の `START_REC.bat` と `STOP_REC.bat` を呼び出しています。また、確認した各 `CaseNo` 行では第2パラメータ（Tag）が空です。現行BATでは空のTagを無効と判定するため、このテスト定義をそのまま実行すると `ArgsValid=0` になり、通常のCase/Tag名では保存されません。

CAPLは `sysExec` の終了コードを確認せず、GAIBU処理後に次コマンド用の値 `1` を返します。そのため、BATが終了コード1を返してもCANoeのテストシーケンス自体は止めず、次のコマンドへ進む設計です。異常の有無はBATの `[RESULT]` 表示と保存結果で確認してください。

## 9. よくある注意点

### CaseNo/Tag不一致

- STARTとSTOPで正規化後のCaseNo/Tagが一致しないと `[ERROR] START and STOP CaseNo/Tag do not match` が出ます。
- 従来方式は日時だけのフォルダ名、新方式は `CaseUnknown_UNKNOWN` へフォールバックします。
- エラー終了しますが、停止処理と、準備できた保存先へのファイル移動は続行します。

### マーカーなし・マーカー不正

- 従来方式は `legacy_session.marker`、新方式は `log_session.marker` と `video_session.marker` を使用します。
- マーカーはBATと同じフォルダに作成され、STOPの最後に削除されます。
- マーカーがない種類は、開始時刻による絞り込みができないため最新1件を選びます。
- 新方式で両マーカーのセッションIDが違う場合は、両マーカーの時刻を破棄します。

### MP4なし

- 選択条件に合うMP4がない場合は `[WARN] No MP4 file matched the selection rule.` が出ます。
- ほかにエラーがなければ警告扱いで、STOPの終了コードは0です。
- `ObsStartSucceeded=0` の場合はMP4移動自体をスキップし、STOPはエラー終了します。

### フォルダ既存時の扱い

- 新方式の親フォルダは再利用します。
- 同じCaseNo/Tag/Repeatの前回子フォルダは、最新1件を `_OLD_` 付きへ退避します。
- 今回作成する子フォルダと完全に同じ名前が残っている場合は、ファイル移動をスキップしてエラー終了します。
- 従来方式の保存先が既存の場合も、ファイル移動をスキップしてエラー終了します。

### 非0終了でもテストを止めない

- 各BATは処理中にエラーを記録しても、可能な後続処理を続けます。
- 最後に `[RESULT] ... ExitCode=0` または `ExitCode=1` を表示します。
- CANoeのGAIBU呼び出しはBATの終了コードを判定しないため、BATが1でもテストシーケンスは継続します。
- 手動実行や別の呼び出し元では、必要に応じて `%ERRORLEVEL%` を確認してください。

## 10. トラブルシュート

| 表示 | 疑う箇所・確認内容 |
| --- | --- |
| `[ERROR] Invalid CaseNo or Tag.` | CaseNoが正の数字か、Tagが空でなく英数字・`_`・`-`だけか確認する |
| `[ERROR] Invalid CaseNo, Tag, or Repeat.` | 上記に加え、Repeatが正の数字か確認する |
| `Status=missing` | 対応するSTARTが未実行、START順序が違う、または前回STOPですでにマーカーが削除された可能性を確認する |
| `Status=invalid` | マーカーが途中状態、破損、または必要項目不足になっていないか確認する。STARTからやり直す |
| `Valid SessionId could not be read from ...log_session.marker` | `START_REC2.bat` が正常に完了してから `START_REC3.bat` を実行したか確認する |
| `Log and video SessionId values do not match` | `START_REC2.bat` と `START_REC3.bat` の間で別セッションのマーカーが混在していないか確認する |
| `START and STOP CaseNo/Tag do not match` | STARTとSTOPへ渡したCaseNo/Tag、およびCANoeの `CaseNo` 行を確認する |
| `OBS start failed` / `OBS stop failed` | OBS起動状態、OBS WebSocketのポート `4455`、認証設定、`obs_record_*.ps1` の配置を確認する |
| `OBS ... timed out after 20 seconds` | OBSまたはPowerShell処理が応答しているか確認する。BAT側は20秒でタイムアウトする |
| `Failed to activate Measurement Setup` | CANoeのウィンドウが存在し、タイトルが一致しているか確認する |
| `Failed to activate COM42 Tera Term` / `COM42 window activation failed` | COM42のTera Termが起動し、ウィンドウタイトルが一致しているか確認する |
| `No MP4 file matched the selection rule.` | OBSが実際に録画したか、MP4が `C:\Users\TMC\Videos\Captures` にあるか、作成時刻が開始時刻以降か確認する |
| `No PNG/LOG/ASC file matched the selection rule.` | 対応する移動元パス、拡張子、作成・更新時刻を確認する |
| `Destination ... already exists` | 同一秒にSTOPしたフォルダや残存フォルダがないか確認する。既存データを確認してから再実行する |
| `Failed to archive the latest previous normal child folder.` | 対象フォルダが使用中でないか、名前変更権限があるか確認する。この場合は新規保存と移動もスキップされる |
| `[RESULT] ... with warnings. ExitCode=0` | 必須停止処理はエラー扱いではないが、ファイルなしやマーカー削除失敗などの警告内容を直前の表示で確認する |
| `[RESULT] ... with errors. ExitCode=1` | 直前までの `[ERROR]` を確認する。CANoeテストは継続するため、結果フォルダも必ず確認する |

## 11. READMEの更新ルール

BAT、PowerShell、CAPLの運用仕様を変更した場合は、同じ変更単位でこのREADMEも更新します。

1. 実行順、引数、固定パス、保存名、失敗時の挙動に変更がないか確認する
2. 変更がある章と実行例を更新する
3. 下の変更履歴へ日付、対象ファイル、運用上の変更点を1行で追記する
4. 推測や未確認の動作は記載せず、実機未確認事項がある場合は明記する

### 変更履歴

| 日付 | 対象 | 内容 |　作成者　|
| --- | --- | --- | --- |
| 2026-07-21 | `README.md` | 現行の従来方式・新方式BATに基づく運用ガイドを作成 | 伊神 |
