(function () {
  // ページのボディ部分のHTMLを取得
  var bodyHtml = document.body.outerHTML;

  // 一時的にtextareaを作成
  var textarea = document.createElement("textarea");
  textarea.value = bodyHtml;
  document.body.appendChild(textarea);

  // テキストを選択してクリップボードにコピー
  textarea.select();
  document.execCommand("copy");

  // textareaを削除
  document.body.removeChild(textarea);

  console.log("ボディ部分のHTMLがクリップボードにコピーされました。");
})();
