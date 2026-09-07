import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

const PROVIDER = 'dotfiles-hourly-gemini';
const MODEL = 'gemini-3.8-flash';

// Pi's OpenAI adapter drops Gemini tool-call thought signatures. Use the
// native adapter for this pipe, retaining the key supplied by its preset.
export default function (pi: ExtensionAPI) {
  pi.registerProvider(PROVIDER, {
    name: 'Hourly report Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    apiKey: '$CUSTOM_API_KEY',
    api: 'google-generative-ai',
    models: [{
      id: MODEL,
      name: 'Gemini 3.8 Flash',
      reasoning: true,
      input: ['text', 'image'],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 1048576,
      maxTokens: 65536,
    }],
  });

  pi.on('session_start', async (_event, ctx) => {
    const selected = ctx.model;
    if (selected?.provider !== 'custom' || selected.id !== MODEL) return;
    const url = new URL(selected.baseUrl);
    if (url.origin !== 'https://generativelanguage.googleapis.com') return;

    const model = ctx.modelRegistry.find(PROVIDER, MODEL);
    if (!model || !(await pi.setModel(model))) {
      throw new Error('Hourly report: native Gemini adapter could not use CUSTOM_API_KEY');
    }
    pi.setThinkingLevel('low');
  });
}
