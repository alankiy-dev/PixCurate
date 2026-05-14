# PixCurate

## プロジェクト概要

Sony・Fujifilm・Canon などのRAW写真ファイルを対象に、メタデータ（★評価・撮影地・タグ）の編集・管理・検索・バックアップを一元化するmacOSアプリ。

StarFileCopyの後継・統合版として開発。

- 言語・フレームワーク: Swift / SwiftUI
- IDE: Xcode
- ターゲット: macOS
- データストア: SQLite（インデックスDB）+ XMPサイドカー（正データ）
- NAS: TrueNAS（SMB共有 `smb://192.168.3.42/photos`）

## 対応RAWフォーマット

| メーカー | 拡張子 | サイドカー |
|---|---|---|
| Fujifilm | `.RAF` | `.xmp` |
| Sony | `.ARW` | `.xmp` |
| Canon | `.CR3` / `.CR2` | `.xmp` |

メタデータの正データはXMPサイドカーに保持する。RAW本体は変更しない。

## 機能一覧

### ① ファイル管理・閲覧
- RAWファイルとXMPをペアで認識・表示
- サムネイル表示（`QLThumbnailGenerator`使用）
- ★・撮影地・タグ・撮影日を一覧表示

### ② メタデータ編集
- 複数ファイルを選択して一括設定
- ★評価（1〜5）
- 撮影地（マスタから選択 or 直接入力）
- タグ（マスタから複数選択）
- XMPサイドカーへの書き込みにExifToolを使用

### ③ フィルタ・検索
- ★の下限フィルタ
- 撮影地・タグ・日付範囲で絞り込み
- 複数タグのAND/OR条件

### ④ インデックス管理
- ファイルをコピーせず、DBでメタデータを仮想管理
- XMPをスキャンしてDB構築・再構築が可能
- 実体ファイルはNASや元フォルダに1つだけ存在する
- DBはあくまでインデックス。XMPが正データ

### ⑤ バックアップ・コピー（StarFileCopyの機能を継承）
- フィルタ結果を指定フォルダ（NAS含む）にコピー
- フォルダ階層構造を保持
- skip-if-same（同名・同サイズはスキップ）
- security-scoped bookmarksでフォルダアクセスを管理

### ⑥ マスタ管理
- 撮影地マスタ（地名・GPS座標・メモ）
- タグマスタ（階層化対応、例：`光芒/朝`・`雲海/大観峰`）
- マスタはSQLiteで保存

## データ設計

### XMPとDBの役割分担

| | XMP | DB（インデックス） |
|---|---|---|
| 正データ | ○ | ✕ |
| 高速検索 | ✕ | ○ |
| ファイル移動時 | 追従する | 要再スキャン |
| バックアップ | RAWと一緒でOK | 別途必要 |

### DBスキーマ（概略）

```sql
-- ファイルインデックス
CREATE TABLE files (
    id INTEGER PRIMARY KEY,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    shot_date TEXT,
    rating INTEGER,
    location_id INTEGER,
    thumbnail_cache BLOB,
    xmp_modified_at TEXT,
    FOREIGN KEY (location_id) REFERENCES locations(id)
);

-- ファイル↔タグ 中間テーブル
CREATE TABLE file_tags (
    file_id INTEGER,
    tag_id INTEGER,
    PRIMARY KEY (file_id, tag_id)
);

-- 撮影地マスタ
CREATE TABLE locations (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    gps_lat REAL,
    gps_lng REAL,
    memo TEXT
);

-- タグマスタ
CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INTEGER,
    FOREIGN KEY (parent_id) REFERENCES tags(id)
);
```

## コーディング規約・注意点

### ファイルアクセス（重要）
- ユーザー選択フォルダは **security-scoped bookmarks** で管理
- `UserDefaults` にbookmarkデータを保存・復元
- `startAccessingSecurityScopedResource()` と `stopAccessingSecurityScopedResource()` は必ず対称で呼ぶ
- サンドボックス制約があるため `FileManager` の直接パス指定は避ける

### ExifTool連携
- XMPの読み書きはExifToolをプロセス呼び出しで使用
- ExifToolはmacOSにインストール済みを前提とする（`/usr/local/bin/exiftool`）
- 書き込み対象はXMPサイドカーのみ。RAW本体は変更しない

### SMB・NAS接続
- NASアドレス: `192.168.3.42`、共有名: `photos`
- macOSのFinderでマウント済みの状態を前提とし、アプリ側でSMBマウント処理は行わない
- マウントポイントは `/Volumes/photos`（環境依存のため決め打ちしない）

### インデックスDB
- DBはXMPをスキャンして再構築できる設計とする（DBが壊れても復元可能）
- ファイルパスが変わった場合は再スキャンで対応
- DBファイルの保存場所: `~/Library/Application Support/PixCurate/index.sqlite`

## ディレクトリ構成（予定）

```
PixCurate/
├── PixCurate.xcodeproj/
├── PixCurate/
│   ├── PixCurateApp.swift
│   ├── ContentView.swift
│   ├── Views/
│   │   ├── FileListView.swift
│   │   ├── MetadataEditView.swift
│   │   ├── FilterView.swift
│   │   └── MasterSettingsView.swift
│   ├── Models/
│   │   ├── PhotoFile.swift
│   │   ├── Location.swift
│   │   └── Tag.swift
│   ├── Services/
│   │   ├── XMPService.swift        # ExifTool呼び出し
│   │   ├── IndexService.swift      # SQLite管理
│   │   ├── CopyService.swift       # バックアップ・コピー
│   │   └── ThumbnailService.swift
│   └── Utilities/
└── ...
```

## 開発ロードマップ

### Phase 1（StarFileCopyの機能移行）
- [ ] RAWファイル一覧表示・サムネイル
- [ ] XMPから★読み取り
- [ ] フィルタ（★・日付）
- [ ] NASへのコピー（StarFileCopyの既存ロジック移植）

### Phase 2（メタデータ編集）
- [ ] ExifTool連携（XMP読み書き）
- [ ] 撮影地・タグの編集UI
- [ ] マスタ管理（撮影地・タグ）
- [ ] Sony ARW・Canon CR3対応

### Phase 3（インデックス管理）
- [ ] SQLiteインデックスDB構築
- [ ] XMPスキャン・DB同期
- [ ] タグ・撮影地による仮想アルバム
- [ ] DB再構築機能

### Phase 4（仕上げ）
- [ ] タグ絞り込み→指定フォルダへコピー
- [ ] 進捗表示・ログ
- [ ] エラーハンドリング改善

## 参考

- [Apple Security-Scoped Bookmarks](https://developer.apple.com/documentation/security/app_sandbox/accessing_files_from_the_macos_app_sandbox)
- [ExifTool公式](https://exiftool.org/)
- [XMP Specification](https://www.adobe.com/devnet/xmp.html)
- [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
