# AutoVisualCheck BAT運用ガイド

## 1. このプロジェクトの目的

このプロジェクトは、CANoeでテストを実行しながら、次の証跡を取得して `%USERPROFILE%\Desktop\LogZips` 配下へまとめるためのものです。

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
- `nircmd.exe`、`obs_record_start.ps1`、`obs_record_stop.ps1` と切り戻し用の `obs_record_start_legacy.ps1`、`obs_record_stop_legacy.ps1` がBATと同じ運用フォルダにあること
- 次の移動元・保存先へアクセスできること。ユーザーデータのパスはBAT実行ユーザーの `%USERPROFILE%` を基準にすること

手動実行する場合は、コマンドプロンプトで次のように運用フォルダへ移動します。

```bat
cd /d C:\Users\TMC\Desktop\Veri\batfile
```

## 3. 引数の共通ルール

| 引数 | 使用BAT | 形式と正規化 |
| --- | --- | --- |
| `CaseNo` | `START_REC.bat`、`STOP_REC.bat`、`START_REC3.bat`、`STOP_REC2.bat` | 1文字以上の数字。先頭の0を除いて管理し、保存名では3桁以上になるよう左側を0埋めする。`0` や数字以外は無効 |
| `Tag` | 同上 | 空欄、または英字、数字、`_`、`-` のみ。保存名と比較時は大文字へ正規化する。空白、日本語、引用符は使用できない |
| `Repeat` | `START_REC.bat`、`STOP_REC.bat`、`STOP_REC2.bat` | 空欄、または1文字以上の数字。先頭の0を除いて管理する。`0` や数字以外は無効 |
| `OperationId` | `START_REC.bat`、`STOP_REC.bat` | CAPLが生成する英数字・`_`・`-`の識別子。手動実行で省略した場合はBATがGUIDを生成する |

例: `CaseNo=1`、`Tag=mm-a`、`Repeat=01` は、保存名ではそれぞれ `001`、`MM-A`、`1` になります。

STARTとSTOPには同じ `CaseNo`、`Tag`、`Repeat` を渡してください。新方式では、`START_REC2.bat` に引数はありません。

## 4. 従来方式の使い方

### 実行順

```text
START_REC.bat [CaseNo] [Tag] [Repeat] [OperationId]
  ↓
テスト本体
  ↓
STOP_REC.bat [CaseNo] [Tag] [Repeat] [OperationId]
```

手動実行例（CaseNo `1`、Tag `MM`）:

```bat
call START_REC.bat 1 MM
rem ここでテスト本体を実行
call STOP_REC.bat 1 MM
```

### `START_REC.bat` の役割

`START_REC.bat [CaseNo] [Tag] [Repeat] [OperationId]` は、次を順番に実行します。CaseNo、Tag、Repeatは空欄でも構いません。

1. `recording_operation.lock` を取得し、OperationId、コマンド名、開始時刻を記録する
2. `legacy_session.marker` を一時ファイル経由で作成し、CaseNo、Tag、Repeat、OperationId、セッションID、開始時刻を記録する
3. `obs_record_start.ps1` を同期実行し、接続・要求・状態確認が内部タイムアウト内に完了するまで待つ
4. PowerShell終了後にだけ、`Measurement Setup` を再確認・アクティブ化してCANログを開始する
5. CAN用NirCmd終了後にだけ、`COM42 - Tera Term VT` を再確認・アクティブ化してTera Termログを開始する
6. Tera Term用NirCmd終了後にスクリーンショットを取得する
7. ロックを解除し、`recording_command.result` を一時ファイル経由で公開する

OBS開始を確認できない場合も、PowerShellプロセスが終了してからCANログ、Tera Termログ、スクリーンショット処理を続けます。この場合の完了状態は `DEGRADED` です。PowerShellと同一BAT内のNirCmd、およびCAN用とTera Term用のNirCmdは直列実行されます。

### `STOP_REC.bat` の役割

`STOP_REC.bat [CaseNo] [Tag] [Repeat] [OperationId]` は、次を順番に実行します。空欄は省略として扱い、入力された項目だけを命名に使用します。

1. `recording_operation.lock` を取得する
2. 引数と `legacy_session.marker` のCaseNo、Tag、Repeatを検証する
3. 対象ウィンドウを再確認してCANログを停止する
4. `obs_record_stop.ps1` を同期実行し、停止完了とOBSが返した `outputPath` を確認する
5. CAN用NirCmdとPowerShellの終了後に、COM42のTera Termログを停止する
6. 保存フォルダを作成し、MP4、PNG、LOG、ASCを移動する
7. `legacy_session.marker` を削除し、ロック解除後に `recording_command.result` を公開する

MP4はOBS WebSocketの `StopRecord` 応答から得た正確な `outputPath` を第一候補とします。利用できない場合だけ最新の安定したMP4を1件選び、結果へ `Mp4SelectionMode=LATEST_FALLBACK` と `EvidenceConfidence=UNVERIFIED_FALLBACK` を記録します。最新MP4がロック中またはサイズ変化中なら移動しません。PNG・LOG・ASCは、マーカーが有効な場合は開始時刻以降の全件、利用できない場合は各種類の最新1件を選びます。

### 完了通知と処理ロック

CANoeから起動する従来方式では、CAPLが `CaseNo Tag Repeat OperationId` を渡し、`recording_command.result` のOperationIdが一致するまで次のスクリプト行を実行しません。

| `State` | CAPLの動作 |
| --- | --- |
| `SUCCEEDED` | 次行へ進む |
| `DEGRADED` | OBS失敗やフォールバック等を観測値へ残し、次行へ進む |
| `FAILED` | 次行へ進まず停止する |

結果ファイル不在・古いOperationIdは待機を継続し、既定180秒で `CAPL_RESULT_TIMEOUT` として停止します。`RecordingHandshakeEnabled=0` にすると従来の非同期進行へ切り戻せます。

自己完結型PowerShellから旧処理へ一時的に切り戻す場合は、CANoeを起動する環境で `RECORDING_USE_LEGACY_OBS_SCRIPT=1` を設定します。旧処理でもBATが最大20秒待ち、タイムアウト時はPowerShellプロセスの終了を確認してからNirCmdへ進みます。終了を確認できない場合は `FAILED` として後続処理を止め、ロックを残します。通常運用は未設定または `0` です。

`recording_operation.lock` が存在する間は別の従来方式START／STOPを開始しません。異常終了でロックが残った場合は自動削除されません。OBSの録画状態と対象のBAT、PowerShell、NirCmdが終了していることを確認してから、運用フォルダ内の `recording_operation.lock` だけを手動で削除してください。

処理時刻は `recording_timeline.log` とCANoe Writeウィンドウの `[REC_TIMELINE]` に記録されます。外部アプリや手動操作によるフォーカス奪取までは防止できないため、ウィンドウなし・複数候補の警告も確認してください。

CaseNoとTagがある場合の保存先は次の形式です。

```text
C:\Users\TMC\Desktop\LogZips\Case{CaseNoを3桁以上に0埋め}_{大文字Tag}_{yyyyMMdd_HHmmss}
```

例:

```text
C:\Users\TMC\Desktop\LogZips\Case001_MM_20260721_143000
```

CaseNoまたはTagが空欄の場合は、存在する項目だけを使用します。両方空欄、STARTとSTOPのCaseNo/Tagが不一致、または有効なSTARTマーカー内の値と一致しない場合は、日時だけの名前を使用します。

```text
C:\Users\TMC\Desktop\LogZips\20260721_143000
```

マーカーがない場合でも、STOP側で入力された有効なCaseNoまたはTagを命名に使用します。空欄ではない不正値は名前から除外し、最終終了コードを1にします。

## 5. 新方式の使い方

### 実行順

```text
START_REC2.bat
  ↓
START_REC3.bat [CaseNo] [Tag]
  ↓
テスト本体
  ↓
STOP_REC2.bat [CaseNo] [Tag] [Repeat]
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

`START_REC3.bat [CaseNo] [Tag]` は録画側の開始処理を担当します。

1. 前回の `video_session.marker` を無効化する
2. 有効なCaseNoまたはTagがあれば、その項目だけで親フォルダを作成または再利用し、両方空欄なら `LogZips` 直下を使用する
3. `log_session.marker` からセッションIDを引き継ぐ
4. 録画開始時刻とCaseNo/Tagを `video_session.marker` に記録する
5. OBS録画を開始し、成功結果を同マーカーへ記録する

有効な `log_session.marker` を読めない場合は、エラーを記録したうえで代替セッションIDを作り、OBS開始処理まで続行します。この場合、STOP時にログ側と録画側のセッション不一致として扱われる可能性があります。

### `STOP_REC2.bat` の役割

`STOP_REC2.bat [CaseNo] [Tag] [Repeat]` は、次を実行します。

1. 引数、`log_session.marker`、`video_session.marker` を個別に検証する
2. 両マーカーが有効ならセッションIDが一致するか検証する
3. CANログ、OBS録画、COM42のTera Termログを停止する
4. 同じCaseNo/Tag/Repeatの前回フォルダを必要に応じて `_OLD_` 付きへ退避する
5. 新しい子フォルダを作り、MP4、PNG、LOG、ASCを移動する
6. 2つのマーカーを削除する

ログ側と録画側のマーカーを個別に扱うため、一方だけが有効な場合は、有効な側では開始時刻を使い、無効な側では最新1件を選ぶフォールバックを使用します。両マーカーのセッションIDが不一致の場合は両方の時刻情報を破棄し、両側とも最新1件を選びます。

## 6. 保存先フォルダとファイル名

### 新方式の保存構造

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

空欄項目は省略し、余分な `_` や `#` は付けません。

| 入力 | 子フォルダ名 |
| --- | --- |
| Case、Tag、Repeat | `Case001_TAG#2_20260721_143000` |
| Case、Tag | `Case001_TAG_20260721_143000` |
| Case、Repeat | `Case001#2_20260721_143000` |
| Tag、Repeat | `TAG#2_20260721_143000` |
| Caseのみ | `Case001_20260721_143000` |
| Tagのみ | `TAG_20260721_143000` |
| Repeatのみ | `Repeat2_20260721_143000` |
| すべて空欄 | `20260721_143000` |

CaseまたはTagがある場合は、それらだけで構成した親フォルダを使用します。CaseとTagが両方空欄なら `LogZips` 直下へ子フォルダを作ります。MP4と他の移動ファイルも同じ命名部品を使用し、すべて空欄の場合は日時をファイル接頭辞にします。

### 新方式の退避フォルダ

新しい子フォルダを作る前に、同じ親フォルダ内から、同じ有効なCaseNo/Tag/Repeatの組合せに完全一致する最新の子フォルダ1件を探します。全項目空欄の場合は日時形式だけのフォルダを対象にします。見つかった場合は次の形式へ名前を変更します。

```text
Case001_MM#1_20260721_130000_OLD_20260721_143000
```

退避先名がすでに存在する場合は、末尾に `_01`、`_02` のような連番を付けます。名前変更に失敗した場合、新しい子フォルダの作成とファイル移動は行いません。すでに `_OLD_` を含むフォルダは退避対象外です。

従来方式にはこの退避処理はありません。STOP日時まで同じ保存先フォルダがすでに存在する場合はエラーとなり、ファイル移動を行いません。

## 7. 移動元のパス一覧

| 種類 | 移動元 | 通常時の選択基準 |
| --- | --- | --- |
| MP4 | `%USERPROFILE%\Videos\Captures` | 録画開始時刻以降に作成されたMP4のうち最新1件 |
| PNG | `%USERPROFILE%\Pictures\Screenshots` | セッション開始時刻以降に作成されたPNG全件 |
| LOG | `C:\teraterm-5.2\log` | ログ開始時刻以降に更新されたLOG全件 |
| ASC | `%USERPROFILE%\Desktop\LogZips\CANtemp` | ログ開始時刻以降に更新されたASC全件 |

ファイルはコピーではなく移動されます。マーカー時刻を利用できない種類では、その種類の最新1件だけを選びます。1件ずつ移動するため、あるファイルの移動失敗後も、同じ種類の残りのファイルや後続種類の処理を続けます。

## 8. CANoeの `GAIBU` 呼び出し

`VERI\CAPL\VERI.can` の `GAIBU` は外部BATを `C:\Users\TMC\Desktop\Veri\batfile` を作業フォルダとして起動します。BAT名に応じて、CANoeのシステム変数から次の引数を組み立てます。

| BAT | GAIBUから渡される引数 |
| --- | --- |
| `START_REC.bat` | `CaseNo Tag Repeat OperationId` |
| `STOP_REC.bat` | `CaseNo Tag Repeat OperationId` |
| `START_REC2.bat` | 引数なし |
| `START_REC3.bat` | `CaseNo Tag` |
| `STOP_REC2.bat` | `CaseNo Tag Repeat` |

従来方式では、`CaseNo` 行の第1パラメータを `RecordingCaseNo` へ保持し、その時点で前ケースの `RecordingRepeat` と `RecordingTag` をクリアします。`Repeat` 行の第1パラメータは `RecordingRepeat`、専用の `Tag` 行の第1パラメータは `RecordingTag` へ保持します。`CaseNo` 行の第2パラメータは従来どおり表示用コメントとして残り、録画Tagには使用しません。新方式の既存引数組み立ては変更していません。

```text
CaseNo<TAB>1<TAB>表示コメント
Repeat<TAB>2<TAB>
Tag<TAB>WB<TAB>
Gaibu<TAB>START_REC.bat<TAB>
```

現在の `MM_前進ミラー開_153Cases.txt` は、従来方式の `START_REC.bat` と `STOP_REC.bat` を呼び出しています。固定の `WaitMS 18000` は、実機で代表3ケース、10ケース、153ケースの順に完了通知を確認するまで残します。安定確認前に削除しないでください。

一般のGAIBUと分割方式は従来どおり `sysExec` 後に進みます。従来方式の `START_REC.bat` と `STOP_REC.bat` だけは完了結果を待ち、`SUCCEEDED`／`DEGRADED`で再開し、`FAILED`／タイムアウトで停止します。

## 9. よくある注意点

### CaseNo/Tag/Repeat不一致

- STARTとSTOPで正規化後のCaseNo/Tag/Repeatが一致しないと `[ERROR] START and STOP CaseNo, Tag, or Repeat do not match` が出ます。
- 従来方式は日時だけのフォルダ名、新方式は有効なRepeatがあれば `Repeat{Repeat}_{日時}`、なければ日時だけの名前へフォールバックします。
- エラー終了しますが、停止処理と、準備できた保存先へのファイル移動は続行します。

### マーカーなし・マーカー不正

- 従来方式は `legacy_session.marker`、新方式は `log_session.marker` と `video_session.marker` を使用します。
- マーカーはBATと同じフォルダに作成され、STOPの最後に削除されます。
- `legacy_session.marker` はVersion 3で、OperationIdとRepeatを追加しています。STOP側はVersion 1・2も読み込み、従来の `UNKNOWN` を空欄として扱います。
- `video_session.marker` は分割方式の既存Versionのままです。
- マーカーがない種類は、開始時刻による絞り込みができないため最新1件を選びます。
- 新方式で両マーカーのセッションIDが違う場合は、両マーカーの時刻を破棄します。

### MP4なし

- 正確なOBS出力パスを利用できない場合は最新MP4フォールバックを試し、必ず `LATEST_FALLBACK`／`UNVERIFIED_FALLBACK` と記録します。
- 最新MP4がない、ロック中、またはサイズ変化中の場合は移動せず `DEGRADED` とします。
- `ObsStartSucceeded=0` でも、停止可能な処理とフォールバック選択は続けます。

### フォルダ既存時の扱い

- 新方式の親フォルダは再利用します。
- 同じCaseNo/Tag/Repeatの前回子フォルダは、最新1件を `_OLD_` 付きへ退避します。
- 今回作成する子フォルダと完全に同じ名前が残っている場合は、ファイル移動をスキップしてエラー終了します。
- 従来方式の保存先が既存の場合も、ファイル移動をスキップしてエラー終了します。

### 完了状態とテスト継続

- 各BATは処理中にエラーを記録しても、可能な後続処理を続けます。
- OBS失敗など後続処理を完了できた異常は `DEGRADED` として公開し、CAPLはテストを続けます。
- ロック取得失敗、結果公開不能、CAPL待機タイムアウトなど完了を保証できない異常は `FAILED` とし、CAPLは停止します。
- 手動実行や別の呼び出し元では、必要に応じて `%ERRORLEVEL%` を確認してください。

## 10. トラブルシュート

| 表示 | 疑う箇所・確認内容 |
| --- | --- |
| `[ERROR] Invalid CaseNo or Tag.` | CaseNoが正の数字か、Tagが空でなく英数字・`_`・`-`だけか確認する |
| `[ERROR] Invalid CaseNo, Tag, or Repeat.` | 上記に加え、Repeatが正の数字か確認する |
| `Status=missing` | 対応するSTARTが未実行、START順序が違う、または前回STOPですでにマーカーが削除された可能性を確認する |
| `Status=invalid` | マーカーが途中状態、破損、または必要項目不足になっていないか確認する。STARTからやり直す |
| `OBS ... script was not found` | `obs_record_start.ps1` または `obs_record_stop.ps1` が実行したBATと同じフォルダにあるか確認する |
| `NirCmd was not found` | `nircmd.exe` が実行したBATと同じフォルダにあるか確認する |
| `Valid SessionId could not be read from ...log_session.marker` | `START_REC2.bat` が正常に完了してから `START_REC3.bat` を実行したか確認する |
| `Log and video SessionId values do not match` | `START_REC2.bat` と `START_REC3.bat` の間で別セッションのマーカーが混在していないか確認する |
| `START and STOP CaseNo, Tag, or Repeat do not match` | STARTとSTOPへ渡したCaseNo/Tag/Repeat、およびCANoeの `CaseNo`、`Repeat`、`Tag` 行を確認する |
| `OBS start failed` / `OBS stop failed` | OBS起動状態、OBS WebSocketのポート `4455`、認証設定、`obs_record_*.ps1` の配置を確認する |
| `OBS_*_TIMEOUT` | OBS WebSocketの接続、要求、状態確認がPowerShell内部の期限を超えた。OBS状態と `obs_start.result`／`obs_stop.result` を確認する |
| `LEGACY_*_TIMEOUT_TERMINATED` | 旧PowerShellが20秒で終了せず、BATが終了を確認してから縮退処理を続けた |
| `OBS_POWERSHELL_TERMINATION_UNCONFIRMED` | 旧PowerShellの終了を確認できなかったため後続処理を停止し、処理ロックを残した |
| `OPERATION_LOCK_BUSY_OR_CREATE_FAILED` | 別の録画BATが処理中か、ロックフォルダを作成できない状態か確認する。残留ロックの場合は関連プロセスとOBS状態を確認してから手動解除する |
| `OPERATION_LOCK_METADATA_FAILED` | 新規ロックの所有者情報を書けなかった。運用フォルダの権限と残留ロックを確認する |
| `CAPL_RESULT_TIMEOUT` | `recording_command.result` の有無、OperationId、BATの停止位置、結果ファイル公開失敗を確認する |
| `LATEST_MP4_FALLBACK` | 正確なOBS出力パスが使えず最新MP4を未確認証跡として選択した。結果内の元パス・時刻・サイズを確認する |
| `Failed to activate Measurement Setup` | CANoeのウィンドウが存在し、タイトルが一致しているか確認する |
| `Failed to activate COM42 Tera Term` / `COM42 window activation failed` | COM42のTera Termが起動し、ウィンドウタイトルが一致しているか確認する |
| `No MP4 file matched the selection rule.` | OBSが実際に録画したか、MP4が `%USERPROFILE%\Videos\Captures` にあるか、作成時刻が開始時刻以降か確認する |
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
