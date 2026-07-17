const dia = {
  name: "company.thebrowser.dia",
  appType: "bundleId",
};

const chrome = {
  name: "com.google.Chrome",
  appType: "bundleId",
};

const discordDomains = [
  "discord.com",
  "discord.gg",
  "discordapp.com",
  "discordapp.net",
];

export default {
  defaultBrowser: dia,

  options: {
    keepRunning: true,
  },

  handlers: [
    {
      match: (url) =>
        discordDomains.some(
          (domain) => url.host === domain || url.host.endsWith(`.${domain}`),
        ),
      browser: chrome,
    },
  ],
};
