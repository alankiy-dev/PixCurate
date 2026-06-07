import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // タイトル
                VStack(alignment: .leading, spacing: 4) {
                    Text("PixCurate ヘルプ")
                        .font(.largeTitle).bold()
                    Text("RAW写真のメタデータ管理・選別・バックアップ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)

                // 開発の背景
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .foregroundStyle(Color.accentColor)
                            .font(.system(size: 13, weight: .semibold))
                        Text("開発の背景")
                            .font(.title3).bold()
                    }

                    Divider()

                    Text("""
                    私の現像プロセスは次のようなものです。撮影した画像はすべてハードディスクに取り込み、現像の際に残したいファイルだけに★評価を付けます。★のないファイルは、試し撮りや構図を変えながら撮った複数カット、ピントが外れた画像など「選外」の画像です。こうした不要ファイルがハードディスクの容量を少しずつ圧迫し、バックアップともなれば消費はさらに増えます。不要な画像をバックアップする必要はありません。
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("""
                    ★を付けた画像だけを現像情報（XMP）と一緒にバックアップしたい——それがこのアプリを作るきっかけでした。不要な画像を削除してしまえば話は早いのですが、見返すと意外と良い一枚が混ざっていることもあり、なかなか踏み切れないものです。
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("""
                    基本機能のバックアップに加えて、タグや撮影地の情報を設定することで目的の画像を絞り込んで表示できる機能も加えました。「あの時期にどの撮影地でどんな被写体を撮ったか」を後から探す用途にも使えます。撮影地ごとにまとめたファイルを専用フォルダにコピーするといった使い方も考えられますが、同じ画像がテーマ別のフォルダに何度もコピーされると、それもディスクを圧迫してしまいます。そこで、実体ファイルはひとつのまま、リンク情報だけを保存して管理する「コレクション」機能も追加しました。
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 8)

                HelpSection(title: "基本的な使い方", icon: "photo.on.rectangle.angled") {
                    HelpItem(label: "コピー元フォルダを選択") {
                        "左パネル「フォルダ」→「コピー元」の「選択」ボタンで、RAWファイルが入ったフォルダを指定します。選択後すぐに読み込みが始まります。"
                    }
                    HelpItem(label: "コピー先フォルダを選択") {
                        "「コピー先」の「選択」ボタンで、バックアップ先（NAS等）を指定します。"
                    }
                    HelpItem(label: "ファイルの選択") {
                        "サムネイルまたは行をクリックで選択。⌘クリックで複数選択、Shiftクリックで範囲選択ができます。"
                    }
                    HelpItem(label: "複数のコピー元フォルダを登録") {
                        "「コピー元」の「選択」ボタン（フォルダ管理ダイアログ）では、複数のフォルダを登録して同時に検索対象にできます。各フォルダごとに「サブフォルダを含む」の有無を設定できます。フォルダがオフライン（未接続）の場合はインジケーターで示され、登録情報は保持されたまま再接続時に自動的に復帰します。"
                    }
                    HelpItem(label: "コピー元フォルダの有効/無効") {
                        "フォルダ管理ダイアログの各フォルダ左端のチェックボックスで、そのフォルダを有効/無効に切り替えられます。チェックを入れたフォルダだけが検索対象になり、タブにも表示されます。一時的に特定フォルダを対象から外したいときに、登録を削除せずに切り替えられます。"
                    }
                    HelpItem(label: "有効/無効切替時の読み込み") {
                        "フォルダを無効にした場合はスキャンを行わず、DBから即座に再読み込みします。新しく有効にしたフォルダがある場合は、その新規フォルダだけをスキャンするため待ち時間を抑えられます。全フォルダの最新状態に更新したいときは、ツールメニュー→「再スキャン」（⌘R）を実行してください。"
                    }
                }

                HelpSection(title: "表示モード", icon: "rectangle.grid.2x2") {
                    HelpItem(label: "グリッド表示") {
                        "サムネイルをグリッド状に並べて表示します。右上の「表示設定」ボタン（スライダーアイコン）でサムネイルサイズ（小・中・大）、バッジ表示のオン/オフを切り替えられます。"
                    }
                    HelpItem(label: "グリッドの並び順") {
                        "グリッドモード時、ツールバー左側に並び順コントロールが表示されます。左のメニュー（↕）でソートキー（ファイル名・撮影日時・評価・撮影地・タグ・XMP更新日）を選択し、右の矢印ボタンで昇順↑・降順↓を切り替えます。設定は次回起動時にも保持されます。"
                    }
                    HelpItem(label: "グリッドのキーボード操作") {
                        "グリッドにカーソルがある状態で矢印キー（←→↑↓）を押すと隣の画像に選択が移動します。画面外に出た場合は自動的にスクロールして追従します。ダブルクリックで拡大表示を開くと、そのコマも選択状態になります。"
                    }
                    HelpItem(label: "縦画像の表示") {
                        "グリッドのサムネイルは縦横比を保ったまま全体を表示します。縦位置で撮影した画像も上下が切れずに表示されます。"
                    }
                    HelpItem(label: "リスト表示") {
                        "ファイル情報を一覧表示します。列ヘッダーをクリックすると昇順→降順→解除の順でソートできます。列の組み合わせは「表示設定」から変更できます。"
                    }
                    HelpItem(label: "表示する列の設定（リスト）") {
                        "「表示設定」→「表示する列」で、撮影日時・評価・撮影地・タグ・XMP更新日・カメラ・レンズ・焦点距離・絞り・SS・ISO・解像度の表示/非表示を切り替えられます。★マークの列はファイルを直接読み込むため表示に少し時間がかかります。"
                    }
                    HelpItem(label: "背景色") {
                        "「表示設定」→「背景色」で写真一覧エリアの背景を「自動」（macOSの標準配色）・「白」・「黒」から選べます。黒背景は暗室モード的な見え方になり、写真の色味を確認しやすくなります。文字色は背景に合わせて自動で切り替わります。"
                    }
                    HelpItem(label: "モード切替時のウィンドウ") {
                        "リスト表示に切り替えると列が収まるようウィンドウが自動的に広がります。グリッドに戻すと標準サイズに戻ります。"
                    }
                    HelpItem(label: "フォルダ別タブ表示") {
                        "コピー元フォルダを複数登録している場合、写真一覧の上部にフォルダごとのタブが表示されます。「すべて」タブは全フォルダを横断して表示し、各フォルダタブはそのフォルダのファイルだけを表示します。タブには「フィルター後の件数 / そのフォルダの総件数」が表示され、有効にしたフォルダだけがタブに並びます。"
                    }
                    HelpItem(label: "タブごとに独立したフィルター") {
                        "各タブはそれぞれ独立したフィルター条件（フォーマット・評価・タグ・撮影地・カラーラベル・撮影日・更新日）を保持します。タブを切り替えると、そのタブで設定していた条件が復元されます。各タブの件数もタブごとの条件で個別に計算されます。フォルダタブの条件はアプリを再起動しても保持されます。"
                    }
                }

                HelpSection(title: "フィルター", icon: "line.3.horizontal.decrease.circle") {
                    HelpItem(label: "フォーマット") {
                        "「RAW」「JPEG」「R & J」の3つのボタンで表示対象のファイル種別を切り替えます。初期値は「RAW」です。"
                    }
                    HelpItem(label: "評価フィルター") {
                        "★をクリックするとその評価で絞り込みます。同じ★をもう一度クリックすると1段階下がり、★1の状態でもう一度クリックすると全件表示（評価なし含む）に戻ります。"
                    }
                    HelpItem(label: "評価フィルターのモード（以上／のみ）") {
                        "★を1つ以上選択すると、★の下に「以上」「のみ」のボタンが表示されます。「以上」はその評価以上の画像をすべて表示（例：★3以上 → ★3・★4・★5）。「のみ」はその評価の画像だけを表示（例：★3のみ → ★3だけ）。初期値は「以上」です。設定は次回起動時にも保持されます。"
                    }
                    HelpItem(label: "タグフィルター") {
                        "タグを選んでフィルタリングできます。同じグループ内は OR 条件、グループをまたぐと AND 条件になります。"
                    }
                    HelpItem(label: "撮影地フィルター") {
                        "撮影地マスタに登録された地名で絞り込みます。複数選択は OR 条件です。"
                    }
                    HelpItem(label: "撮影日フィルター") {
                        "撮影日セクションにある3つのアイコンで絞り込みモードを切り替えます。「−」はフィルターなし、時計アイコン（↻）は「例年の今頃」、カレンダーアイコンは「期間指定」です。"
                    }
                    HelpItem(label: "例年の今頃") {
                        "時計アイコンを選ぶと、年をまたいで「今日の月日から前後N日以内」の写真を全年から絞り込みます。「前後〇日間」に0〜99を入力し、フィルターアイコン（⊙）またはReturnキーで適用します。0日は今日と同じ月日のみ、14日なら前後2週間が対象です。「去年の今頃どこに撮りに行ったか」を振り返る用途に便利です。"
                    }
                    HelpItem(label: "期間指定") {
                        "カレンダーアイコンを選ぶと、From・Toで撮影日の範囲を指定して絞り込みます。特定の撮影日のファイルだけを対象にコピーしたい場合などに便利です。"
                    }
                    HelpItem(label: "更新日フィルター") {
                        "「更新日フィルター」をオンにすると、指定した日付以降にXMPが更新された画像だけを表示します。当日のみ確認したい場合などに便利です。"
                    }
                    HelpItem(label: "カラーラベルフィルター") {
                        "左パネル「フィルター」→「カラーラベル」のしおりアイコンをクリックして絞り込みます。複数の色を選択すると OR 条件になります。同じアイコンを再クリックすると解除されます。"
                    }
                    HelpItem(label: "プリセット") {
                        "「現在の条件を保存...」で評価・タグ・撮影地フィルターの組み合わせを名前付きで保存できます。保存したプリセットをクリックするとワンタッチで条件を復元できます。"
                    }
                }

                HelpSection(title: "メタデータ編集", icon: "star.fill") {
                    HelpItem(label: "評価をキーボードで設定") {
                        "画像を選択した状態でキーボードの 1〜5 キーを押すと評価を設定、0 キーで評価を解除します。複数選択中は全てに一括適用され、XMPサイドカーへ即座に書き込まれます。"
                    }
                    HelpItem(label: "評価を右パネルで設定") {
                        "右パネル「評価」タブでサムネイルをクリックして評価を設定します。星をクリックすると即座に書き込まれます。同じ星をもう一度クリックすると解除できます。複数選択中は全てに一括適用されます。"
                    }
                    HelpItem(label: "評価を右クリックメニューで設定") {
                        "サムネイルや行を右クリック→「評価を設定」から評価を変更できます。"
                    }
                    HelpItem(label: "カラーラベルをキーボードで設定") {
                        "画像を選択した状態で R（赤）・Y（黄）・G（緑）・B（青）・P（紫）キーを押すとカラーラベルを設定できます。同じキーをもう一度押すか X キーでラベルを解除します。複数選択中は全てに一括適用されます。XMPサイドカーの xmp:Label フィールドに書き込まれます（Lightroom 互換）。"
                    }
                    HelpItem(label: "カラーラベルを右パネルで設定") {
                        "右パネル「評価」タブの「カラーラベル」セクションにある5色のしおりアイコンをクリックして設定します。同じアイコンをもう一度クリックすると解除できます。即座に書き込まれます。"
                    }
                    HelpItem(label: "カラーラベルを右クリックメニューで設定") {
                        "サムネイルや行を右クリック→「カラーラベルを設定」から色を選択できます。「解除」を選ぶとラベルを消去します。複数選択中は一括適用されます。"
                    }
                    HelpItem(label: "カラーラベルの表示") {
                        "カラーラベルが設定された画像のサムネイル右上に、設定した色のしおりアイコンが表示されます。拡大表示ウィンドウの下部バーにも色付きドットが表示されます。"
                    }
                    HelpItem(label: "拡大表示での評価・ラベル設定") {
                        "拡大表示ウィンドウでも 1〜5 キーで評価を設定（0で解除）、R/Y/G/B/P キーでカラーラベルを設定できます。設定内容はウィンドウ中央にフィードバック表示されてフェードアウトし、メイン画面にも即座に反映されます。"
                    }
                    HelpItem(label: "拡大表示を閉じる") {
                        "拡大表示ウィンドウで Esc キーを押すと閉じます。"
                    }
                    HelpItem(label: "撮影地の検索") {
                        "右パネル「撮影地」タブの検索フィールドに地名を入力すると、マスタ登録済みの撮影地を絞り込んで表示します。検索結果にはフルパス（例：大分県 › 由布市 › 金鱗湖）も表示されるため、同名の地名が別の場所にある場合でも区別できます。"
                    }
                    HelpItem(label: "タグの表示") {
                        "サムネイルバッジおよびリスト列には、設定されたタグをすべて表示します。スペースが足りない場合は末尾が省略されます。"
                    }
                    HelpItem(label: "EXIF情報を表示") {
                        "右クリック→「情報を表示」で、カメラ・レンズ・焦点距離・絞り・シャッタースピード・ISO・解像度などのEXIF情報を確認できます。"
                    }
                    HelpItem(label: "拡大表示") {
                        "ダブルクリックで画像を別ウィンドウに拡大表示します。縦位置画像も正しく縦向きで表示されます。"
                    }
                    HelpItem(label: "拡大表示のサイズ") {
                        "「表示設定」→「拡大表示のサイズ」で、ダブルクリックで開くときの初期サイズを「通常」「画面に合わせる」「ピクセル等倍」から選べます。「画面に合わせる」は画像全体が画面に収まる最大サイズ、「ピクセル等倍」は原寸（1ピクセル＝1ドット）で表示します。初期値は「画面に合わせる」です。"
                    }
                    HelpItem(label: "サイズを指定して拡大表示") {
                        "右クリックメニューの「通常サイズで表示」「画面に合わせて表示」「ピクセル等倍で表示」から、その場でサイズを指定して開くこともできます。"
                    }
                }

                HelpSection(title: "コピー機能", icon: "arrow.right.circle") {
                    HelpItem(label: "プレビュー") {
                        "「プレビュー」ボタンで、実際にはコピーせず対象ファイルをログに一覧表示します。コピー前の確認に使います。"
                    }
                    HelpItem(label: "コピー実行") {
                        "「コピー実行」ボタンで、現在フィルターされているファイルをコピー先へ一括コピーします。同名・同サイズのファイルはスキップされます。コピー完了後にデスクトップ通知が届きます。"
                    }
                    HelpItem(label: "フォルダ構造を維持") {
                        "オンにすると、コピー元フォルダからの相対パスを保ったままコピー先にフォルダを再現します。オフにするとコピー先のルートに全ファイルを平置きします。"
                    }
                }

                HelpSection(title: "コレクション", icon: "rectangle.stack") {
                    HelpItem(label: "コレクションとは") {
                        "実体ファイルを複製せず、ファイルへのリンク情報だけを保存してテーマ別にまとめる機能です。「男池をテーマにした写真展」「コンテスト応募作品」など、目的ごとに任意の画像をグループ化できます。同じファイルを複数のコレクションに入れてもディスクを消費しません。"
                    }
                    HelpItem(label: "コレクションを作成") {
                        "左パネル「コレクション」横の「＋」ボタンで新規作成します。名前を入力するだけで作成でき、後から鉛筆アイコンでリネームできます。"
                    }
                    HelpItem(label: "ファイルをコレクションに追加") {
                        "画像を右クリック→「コレクションに追加」→コレクション名を選択します。複数選択した状態で右クリックすると、選択したファイルをまとめて追加できます。「新規コレクションを作成して追加…」を選ぶと、コレクション作成と同時に追加できます。"
                    }
                    HelpItem(label: "コレクションを表示") {
                        "左パネルのコレクション名をクリックするとコレクション内のファイルが表示されます。もう一度クリックするとフォルダ表示に戻ります。表示中もフィルター機能は使用できます。"
                    }
                    HelpItem(label: "ファイルをコレクションから削除") {
                        "コレクション表示中に画像を右クリック→「このコレクションから削除」を選びます。実体ファイルは削除されません。"
                    }
                    HelpItem(label: "コレクションをエクスポート") {
                        "コレクション表示中、上部の「エクスポート」ボタンをクリックし、コピー先フォルダを選択します。確認ダイアログにコレクション名・件数・コピー先が表示されます。接続されていないディスクのファイルがある場合は、ボリューム名と件数が表示され、スキップして続行するか確認できます。"
                    }
                    HelpItem(label: "ディスク未接続時の表示") {
                        "コレクションに含まれるファイルが存在するディスクが接続されていない場合、サムネイル欄にドライブのアイコンとボリューム名が表示されます。ファイル名・評価・タグなどのメタデータはそのまま閲覧できます。"
                    }
                }

                HelpSection(title: "データ出力", icon: "tablecells.badge.ellipsis") {
                    HelpItem(label: "Excel（xlsx）に出力") {
                        "ツールバー右端の表（xlsx）アイコンをクリックすると、現在フィルターされているファイルの一覧を Excel 形式（.xlsx）で書き出します。サムネイル画像・ファイル名・撮影日時・評価・撮影地・タグ・XMP更新日のほか、表示設定でオンにしているカメラ・レンズ・焦点距離など EXIF 列も含まれます。出力には各ファイルの EXIF を読み込む処理があるため、件数が多い場合は少し時間がかかります。"
                    }
                    HelpItem(label: "出力レイアウト") {
                        "先頭列「サムネイル」に縮小画像（120×90px 以内・アスペクト比維持）が埋め込まれ、画像はセル内に中央配置されます。ヘッダー行は青背景・白太字、データ行は罫線付きで出力されます。列幅はリスト表示の列設定に合わせて自動調整されます。"
                    }
                }

                HelpSection(title: "マスタ管理", icon: "list.bullet.rectangle") {
                    HelpItem(label: "タグマスタ") {
                        "左パネル下部の「タグ管理」からタグの追加・編集・削除ができます。"
                    }
                    HelpItem(label: "撮影地マスタ") {
                        "左パネル下部の「撮影地管理」から撮影地の追加・編集・削除ができます。県・市・場所の3階層で管理できます。"
                    }
                    HelpItem(label: "撮影地の重複チェック") {
                        "同じ階層にすでに同名の撮影地が存在する場合は追加できません。重複している場合はアラートが表示されます。大文字・小文字の違いは無視されます。"
                    }
                    HelpItem(label: "削除の確認") {
                        "コレクション・プリセット・タグ・撮影地のゴミ箱アイコンをクリックすると、削除確認ダイアログが表示されます。「削除」を押すまで実際には削除されません。この操作は元に戻せません。"
                    }
                }

                HelpSection(title: "インデックス管理", icon: "cylinder") {
                    HelpItem(label: "再スキャン") {
                        "ツールメニュー→「再スキャン」（⌘R）で、フォルダの差分をスキャンしてDBを更新します。新しく追加したファイルや変更されたXMPを反映します。"
                    }
                    HelpItem(label: "DB再構築") {
                        "ツールメニュー→「DB再構築」でDBを全削除して最初からスキャンし直します。DBが破損した場合や完全な再構築が必要なときに使います。"
                    }
                }

                HelpSection(title: "ウィンドウ操作", icon: "macwindow") {
                    HelpItem(label: "サイドバーの表示切替") {
                        "タイトルバー左端のアイコン（□）でフィルターパネルを折りたたみ・展開できます。リスト表示で列幅が足りない場合に隠すと広くなります。"
                    }
                    HelpItem(label: "ウィンドウサイズの記憶") {
                        "アプリを終了する前のウィンドウの位置・サイズ・最大化状態が自動的に保存され、次回起動時に復元されます。"
                    }
                    HelpItem(label: "画面状態の初期化") {
                        "ウィンドウメニュー→「画面状態の初期化」でグリッド表示・標準サイズ・各種設定のデフォルト値に一括リセットします。"
                    }
                }

                HelpSection(title: "キーボードショートカット", icon: "keyboard") {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            ShortcutRow(key: "1〜5", desc: "評価を設定")
                            ShortcutRow(key: "0", desc: "評価を解除")
                            ShortcutRow(key: "R", desc: "カラーラベル：赤（再押しで解除）")
                            ShortcutRow(key: "Y", desc: "カラーラベル：黄（再押しで解除）")
                            ShortcutRow(key: "G", desc: "カラーラベル：緑（再押しで解除）")
                            ShortcutRow(key: "B", desc: "カラーラベル：青（再押しで解除）")
                            ShortcutRow(key: "P", desc: "カラーラベル：紫（再押しで解除）")
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 6) {
                            ShortcutRow(key: "X", desc: "カラーラベルを解除")
                            ShortcutRow(key: "←→↑↓", desc: "グリッド移動")
                            ShortcutRow(key: "⌘クリック", desc: "複数選択")
                            ShortcutRow(key: "Shiftクリック", desc: "範囲選択")
                            ShortcutRow(key: "ダブルクリック", desc: "拡大表示")
                            ShortcutRow(key: "Esc", desc: "拡大表示を閉じる")
                            ShortcutRow(key: "⌘R", desc: "再スキャン")
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(32)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Parts

private struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.title3).bold()
            }
            .padding(.top, 20)

            Divider()

            content()
        }
        .padding(.bottom, 8)
    }
}

private struct HelpItem<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    // convenience init for plain String content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.callout).bold()
            content()
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

// HelpItem with String shorthand
private extension HelpItem where Content == Text {
    init(label: String, body: () -> String) {
        self.label = label
        let text = body()
        self.content = { Text(text) }
    }
}

private struct ShortcutRow: View {
    let key: String
    let desc: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            Text(desc)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
