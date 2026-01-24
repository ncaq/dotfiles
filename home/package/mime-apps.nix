{
  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      # webブラウザ
      "application/x-extension-htm" = [ "firefox.desktop" ];
      "application/x-extension-html" = [ "firefox.desktop" ];
      "application/x-extension-shtml" = [ "firefox.desktop" ];
      "application/x-extension-xht" = [ "firefox.desktop" ];
      "application/x-extension-xhtml" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "text/html" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];

      # メールクライアント
      "application/ics" = [ "thunderbird.desktop" ];
      "message/rfc822" = [ "thunderbird.desktop" ];
      "text/calendar" = [ "thunderbird.desktop" ];
      "text/vcard" = [ "thunderbird.desktop" ];
      "text/x-vcard" = [ "thunderbird.desktop" ];
      "x-scheme-handler/mailto" = [ "thunderbird.desktop" ];
      "x-scheme-handler/mid" = [ "thunderbird.desktop" ];
      "x-scheme-handler/webcal" = [ "thunderbird.desktop" ];
      "x-scheme-handler/webcals" = [ "thunderbird.desktop" ];

      # テキストエディタ
      "application/json" = [ "emacsclient.desktop" ];
      "application/toml" = [ "emacsclient.desktop" ];
      "application/x-shellscript" = [ "emacsclient.desktop" ];
      "application/x-yaml" = [ "emacsclient.desktop" ];
      "application/xml" = [ "emacsclient.desktop" ];
      "text/markdown" = [ "emacsclient.desktop" ];
      "text/plain" = [ "emacsclient.desktop" ];
      "text/x-c++hdr" = [ "emacsclient.desktop" ];
      "text/x-c++src" = [ "emacsclient.desktop" ];
      "text/x-chdr" = [ "emacsclient.desktop" ];
      "text/x-cmake" = [ "emacsclient.desktop" ];
      "text/x-csrc" = [ "emacsclient.desktop" ];
      "text/x-diff" = [ "emacsclient.desktop" ];
      "text/x-java" = [ "emacsclient.desktop" ];
      "text/x-makefile" = [ "emacsclient.desktop" ];
      "text/x-markdown" = [ "emacsclient.desktop" ];
      "text/x-patch" = [ "emacsclient.desktop" ];
      "text/x-python" = [ "emacsclient.desktop" ];
      "text/x-script.python" = [ "emacsclient.desktop" ];
      "text/x-shellscript" = [ "emacsclient.desktop" ];
      "text/xml" = [ "emacsclient.desktop" ];
      "text/yaml" = [ "emacsclient.desktop" ];

      # ファイルマネージャ
      "application/gzip" = [ "org.gnome.Nautilus.desktop" ];
      "application/vnd.rar" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-7z-compressed" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-arj" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-bzip" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-bzip2" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-compress" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-cpio" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-directory" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-gzip" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-lha" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-lzip" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-lzma" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-rar" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-tar" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-xz" = [ "org.gnome.Nautilus.desktop" ];
      "application/x-zstd" = [ "org.gnome.Nautilus.desktop" ];
      "application/zip" = [ "org.gnome.Nautilus.desktop" ];
      "application/zstd" = [ "org.gnome.Nautilus.desktop" ];
      "inode/directory" = [ "org.gnome.Nautilus.desktop" ];

      # PDFビューア
      "application/pdf" = [ "org.gnome.Evince.desktop" ];
      "application/postscript" = [ "org.gnome.Evince.desktop" ];
      "application/x-bzpdf" = [ "org.gnome.Evince.desktop" ];
      "application/x-dvi" = [ "org.gnome.Evince.desktop" ];
      "application/x-eps" = [ "org.gnome.Evince.desktop" ];
      "application/x-gzpdf" = [ "org.gnome.Evince.desktop" ];
      "application/x-pdf" = [ "org.gnome.Evince.desktop" ];
      "application/x-xzpdf" = [ "org.gnome.Evince.desktop" ];
      "image/x-eps" = [ "org.gnome.Evince.desktop" ];

      # 画像ビューア
      "image/avif" = [ "org.gnome.eog.desktop" ];
      "image/bmp" = [ "org.gnome.eog.desktop" ];
      "image/gif" = [ "org.gnome.eog.desktop" ];
      "image/heic" = [ "org.gnome.eog.desktop" ];
      "image/heif" = [ "org.gnome.eog.desktop" ];
      "image/jpeg" = [ "org.gnome.eog.desktop" ];
      "image/jpg" = [ "org.gnome.eog.desktop" ];
      "image/png" = [ "org.gnome.eog.desktop" ];
      "image/svg+xml" = [ "org.gnome.eog.desktop" ];
      "image/tiff" = [ "org.gnome.eog.desktop" ];
      "image/vnd.microsoft.icon" = [ "org.gnome.eog.desktop" ];
      "image/webp" = [ "org.gnome.eog.desktop" ];
      "image/x-bmp" = [ "org.gnome.eog.desktop" ];
      "image/x-ico" = [ "org.gnome.eog.desktop" ];

      # 動画プレーヤー
      "video/3gpp" = [ "vlc.desktop" ];
      "video/mp4" = [ "vlc.desktop" ];
      "video/mpeg" = [ "vlc.desktop" ];
      "video/ogg" = [ "vlc.desktop" ];
      "video/quicktime" = [ "vlc.desktop" ];
      "video/webm" = [ "vlc.desktop" ];
      "video/x-flv" = [ "vlc.desktop" ];
      "video/x-m4v" = [ "vlc.desktop" ];
      "video/x-matroska" = [ "vlc.desktop" ];
      "video/x-msvideo" = [ "vlc.desktop" ];

      # 音声プレーヤー
      "audio/aac" = [ "vlc.desktop" ];
      "audio/flac" = [ "vlc.desktop" ];
      "audio/mp3" = [ "vlc.desktop" ];
      "audio/mp4" = [ "vlc.desktop" ];
      "audio/mpeg" = [ "vlc.desktop" ];
      "audio/ogg" = [ "vlc.desktop" ];
      "audio/opus" = [ "vlc.desktop" ];
      "audio/wav" = [ "vlc.desktop" ];
      "audio/webm" = [ "vlc.desktop" ];
      "audio/x-flac" = [ "vlc.desktop" ];
      "audio/x-m4a" = [ "vlc.desktop" ];
      "audio/x-vorbis+ogg" = [ "vlc.desktop" ];
      "audio/x-wav" = [ "vlc.desktop" ];

      # LibreOffice Writer
      "application/msword" = [ "writer.desktop" ];
      "application/rtf" = [ "writer.desktop" ];
      "application/vnd.ms-word.document.macroEnabled.12" = [ "writer.desktop" ];
      "application/vnd.oasis.opendocument.text" = [ "writer.desktop" ];
      "application/vnd.oasis.opendocument.text-template" = [ "writer.desktop" ];
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [ "writer.desktop" ];
      "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = [ "writer.desktop" ];
      "text/rtf" = [ "writer.desktop" ];

      # LibreOffice Calc
      "application/vnd.ms-excel" = [ "calc.desktop" ];
      "application/vnd.ms-excel.sheet.macroEnabled.12" = [ "calc.desktop" ];
      "application/vnd.oasis.opendocument.spreadsheet" = [ "calc.desktop" ];
      "application/vnd.oasis.opendocument.spreadsheet-template" = [ "calc.desktop" ];
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [ "calc.desktop" ];
      "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = [ "calc.desktop" ];
      "text/csv" = [ "calc.desktop" ];

      # LibreOffice Impress
      "application/vnd.ms-powerpoint" = [ "impress.desktop" ];
      "application/vnd.ms-powerpoint.presentation.macroEnabled.12" = [ "impress.desktop" ];
      "application/vnd.oasis.opendocument.presentation" = [ "impress.desktop" ];
      "application/vnd.oasis.opendocument.presentation-template" = [ "impress.desktop" ];
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [ "impress.desktop" ];
      "application/vnd.openxmlformats-officedocument.presentationml.template" = [ "impress.desktop" ];

      # LibreOffice Draw
      "application/vnd.ms-visio.drawing" = [ "draw.desktop" ];
      "application/vnd.oasis.opendocument.graphics" = [ "draw.desktop" ];
      "application/vnd.oasis.opendocument.graphics-template" = [ "draw.desktop" ];
      "application/vnd.visio" = [ "draw.desktop" ];

      # アプリケーションのカスタムURLスキーム
      "x-scheme-handler/claude" = [ "claude.desktop" ];
      "x-scheme-handler/discord" = [ "discord.desktop" ];
      "x-scheme-handler/keybase" = [ "keybase.desktop" ];
      "x-scheme-handler/slack" = [ "slack.desktop" ];
      "x-scheme-handler/zoommtg" = [ "Zoom.desktop" ];
      "x-scheme-handler/zoomus" = [ "Zoom.desktop" ];
    };
  };
}
