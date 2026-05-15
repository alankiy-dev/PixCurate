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
                }

                HelpSection(title: "表示モード", icon: "rectangle.grid.2x2") {
                    HelpItem(label: "グリッド表示") {
                        "サムネイルをグリッド状に並べて表示します。右上の「表示設定」ボタン（スライダーアイコン）でサムネイルサイズ（小・中・大）、バッジ表示のオン/オフを切り替えられます。"
                    }
                    HelpItem(label: "リスト表示") {
                        "ファイル情報を一覧表示します。列ヘッダーをクリックすると昇順→降順→解除の順でソートできます。列の組み合わせは「表示設定」から変更できます。"
                    }
                    HelpItem(label: "表示する列の設定（リスト）") {
                        "「表示設定」→「表示する列」で、撮影日時・評価・撮影地・タグ・XMP更新日・カメラ・レンズ・焦点距離・絞り・SS・ISO・解像度の表示/非表示を切り替えられます。★マークの列はファイルを直接読み込むため表示に少し時間がかかります。"
                    }
                    HelpItem(label: "モード切替時のウィンドウ") {
                        "リスト表示に切り替えると列が収まるようウィンドウが自動的に広がります。グリッドに戻すと標準サイズに戻ります。"
                    }
                }

                HelpSection(title: "フィルター", icon: "line.3.horizontal.decrease.circle") {
                    HelpItem(label: "評価フィルター") {
                        "★の数で下限を設定します。「全」を選ぶと評価なしの画像も含め全件表示します。"
                    }
                    HelpItem(label: "タグフィルター") {
                        "タグを選んでフィルタリングできます。同じグループ内は OR 条件、グループをまたぐと AND 条件になります。"
                    }
                    HelpItem(label: "撮影地フィルター") {
                        "撮影地マスタに登録された地名で絞り込みます。複数選択は OR 条件です。"
                    }
                    HelpItem(label: "更新日フィルター") {
                        "「更新日フィルター」をオンにすると、指定した日付以降にXMPが更新された画像だけを表示します。当日のみ確認したい場合などに便利です。"
                    }
                    HelpItem(label: "プリセット") {
                        "「現在の条件を保存...」で評価・タグ・撮影地フィルターの組み合わせを名前付きで保存できます。保存したプリセットをクリックするとワンタッチで条件を復元できます。"
                    }
                }

                HelpSection(title: "メタデータ編集", icon: "star.fill") {
                    HelpItem(label: "キーボードで評価を設定") {
                        "画像を選択した状態でキーボードの 1〜5 キーを押すと評価を設定、0 キーで評価を解除します。複数選択中は全てに一括適用され、XMPサイドカーへ即座に書き込まれます。"
                    }
                    HelpItem(label: "右クリックメニューで評価を設定") {
                        "サムネイルや行を右クリック→「評価を設定」から評価を変更できます。"
                    }
                    HelpItem(label: "EXIF情報を表示") {
                        "右クリック→「情報を表示」で、カメラ・レンズ・焦点距離・絞り・シャッタースピード・ISO・解像度などのEXIF情報を確認できます。"
                    }
                    HelpItem(label: "拡大表示") {
                        "ダブルクリックまたは右クリック→「大きく表示」で画像を別ウィンドウに拡大表示します。"
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
                    HelpItem(label: "画面状態の初期化") {
                        "ウィンドウメニュー→「画面状態の初期化」でグリッド表示・標準サイズ・各種設定のデフォルト値に一括リセットします。"
                    }
                }

                HelpSection(title: "キーボードショートカット", icon: "keyboard") {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            ShortcutRow(key: "0", desc: "評価を解除")
                            ShortcutRow(key: "1〜5", desc: "評価を設定")
                            ShortcutRow(key: "⌘R", desc: "再スキャン")
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 6) {
                            ShortcutRow(key: "⌘クリック", desc: "複数選択")
                            ShortcutRow(key: "Shiftクリック", desc: "範囲選択")
                            ShortcutRow(key: "ダブルクリック", desc: "拡大表示")
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
