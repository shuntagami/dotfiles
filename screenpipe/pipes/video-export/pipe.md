---
schedule: manual
enabled: true
template: true
title: 画面動画を書き出し
description: "直近の画面アクティビティを動画として書き出す"
icon: "🎬"
featured: false
---

直近5分間の画面アクティビティを動画として書き出してください。

最初に screenpipe skill を読んでください。

指定した時間範囲と `fps=1.0` で `POST /frames/export` エンドポイントを使ってください。その後、書き出された動画ファイルのパスをインラインコードで表示してください。

書き出しサイズが大きい場合は、fpsを下げるか、時間範囲を短くする提案をしてください。
