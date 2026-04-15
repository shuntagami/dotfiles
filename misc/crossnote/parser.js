({
  onWillParseMarkdown: async function (markdown) {
    // ========================
    // SVG ICON DEFINITIONS
    // ========================
    const SVG_ICONS = {
      memo: `
    <svg width="20" height="20" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path d="M471.6 21.7c-21.9-21.9-57.3-21.9-79.2 0L362.3 51.7l97.9 97.9 30.1-30.1c21.9-21.9 21.9-57.3 0-79.2L471.6 21.7zm-299.2 220c-6.1 6.1-10.8 13.6-13.5 21.9l-29.6 88.8c-2.9 8.6-.6 18.1 5.8 24.6s15.9 8.7 24.6 5.8l88.8-29.6c8.2-2.7 15.7-7.4 21.9-13.5L437.7 172.3 339.7 74.3 172.4 241.7zM96 64C43 64 0 107 0 160V416c0 53 43 96 96 96H352c53 0 96-43 96-96V320c0-17.7-14.3-32-32-32s-32 14.3-32 32v96c0 17.7-14.3 32-32 32H96c-17.7 0-32-14.3-32-32V160c0-17.7 14.3-32 32-32h96c17.7 0 32-14.3 32-32s-14.3-32-32-32H96z"/>
    </svg>
  `,
      info: `
    <svg width="20" height="20" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path d="M256 512A256 256 0 1 0 256 0a256 256 0 1 0 0 512zM216 336h24V272H216c-13.3 0-24-10.7-24-24s10.7-24 24-24h48c13.3 0 24 10.7 24 24v88h8c13.3 0 24 10.7 24 24s-10.7 24-24 24H216c-13.3 0-24-10.7-24-24s10.7-24 24-24zm40-208a32 32 0 1 1 0 64 32 32 0 1 1 0-64z"/>
    </svg>
  `,
      checkBox: `
    <svg width="20" height="20" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path d="M256 512A256 256 0 1 0 256 0a256 256 0 1 0 0 512zM369 209L241 337c-9.4 9.4-24.6 9.4-33.9 0l-64-64c-9.4-9.4-9.4-24.6 0-33.9s24.6-9.4 33.9 0l47 47L335 175c9.4-9.4 24.6-9.4 33.9 0s9.4 24.6 0 33.9z"/>
    </svg>
  `,
      exclamation: `
    <svg width="20" height="20" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path d="M256 512A256 256 0 1 0 256 0a256 256 0 1 0 0 512zm0-384c13.3 0 24 10.7 24 24V264c0 13.3-10.7 24-24 24s-24-10.7-24-24V152c0-13.3 10.7-24 24-24zM224 352a32 32 0 1 1 64 0 32 32 0 1 1 -64 0z"/>
    </svg>
  `,
      xmark: `
    <svg width="20" height="20" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path d="M256 512A256 256 0 1 0 256 0a256 256 0 1 0 0 512zM175 175c9.4-9.4 24.6-9.4 33.9 0l47 47 47-47c9.4-9.4 24.6-9.4 33.9 0s9.4 24.6 0 33.9l-47 47 47 47c9.4 9.4 9.4 24.6 0 33.9s-24.6 9.4-33.9 0l-47-47-47 47c-9.4 9.4-24.6 9.4-33.9 0s-9.4-24.6 0-33.9l47-47-47-47c-9.4-9.4-9.4-24.6 0-33.9z"/>
    </svg>
  `,
    };

    // ========================
    // CALLOUT TYPE DEFINITIONS
    // ========================
    const CALLOUT_TYPES = [
      { type: 'memo', icon: SVG_ICONS.memo },
      { type: 'alert', icon: SVG_ICONS.xmark },
      { type: 'info', icon: SVG_ICONS.info },
      { type: 'warn', icon: SVG_ICONS.exclamation },
      // { type: "success", icon: SVG_ICONS.checkBox }, // 追加したければ有効化
    ];

    // ========================
    // REPLACE :::type ... ::: WITH HTML
    // ========================
    function replaceCallout(markdown, type, icon) {
      const regex = new RegExp(`:::${type}[\\s\\S]*?:::`, 'gm');

      markdown = markdown.replace(regex, (match) => {
        // 先頭の ":::type" と末尾の ":::"
        const rawContent = match.slice(type.length + 3, -3).trimStart();
        const content = '\n' + rawContent;

        return `
<div class="InlineCalloutElement callout-${type}">
  <div class="IconContainer">${icon}</div>
  <div class="ContentContainer">${content}</div>
</div>
`;
      });

      return markdown;
    }

    for (const { type, icon } of CALLOUT_TYPES) {
      markdown = replaceCallout(markdown, type, icon);
    }

    return markdown;
  },

  onDidParseMarkdown: async function (html) {
    // ここで後処理をしたい場合は追記する
    return html;
  },
});
