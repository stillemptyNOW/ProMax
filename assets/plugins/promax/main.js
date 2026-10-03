import { chat, ui } from 'komet:api';

function textOf(context) {
  return String(context.arguments.text || (context.reply && context.reply.text) || '').trim();
}

async function send(text) {
  if (!text) {
    await ui.notify('Добавьте текст после команды или ответьте на сообщение');
    return;
  }
  if (text.length > 8000) {
    await ui.notify('Используйте текст до 8000 символов');
    return;
  }
  await chat.sendText(text);
}

export async function help() {
  await ui.notify('ProMax Tools: /pmfix — раскладка; /pmclean — очистка текста; /pmchecklist — чек-лист; /pmchoose — выбор. Пункты разделяются символом |.');
}

export async function fix(context) {
  const text = textOf(context);
  const english = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
  const russian = 'йцукенгшщзхъфывапролджэячсмитьбю';
  const toRussian = (text.match(/[a-z]/gi) || []).length >= (text.match(/[а-яё]/gi) || []).length;
  const source = toRussian ? english : russian;
  const target = toRussian ? russian : english;
  const result = [...text].map(character => {
    const lower = character.toLowerCase();
    const index = source.indexOf(lower);
    if (index < 0) return character;
    return character !== lower ? target[index].toUpperCase() : target[index];
  }).join('');
  await send(result);
}

export async function clean(context) {
  const text = textOf(context)
    .replace(/[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]/g, '')
    .replace(/[^\S\r\n]+/g, ' ')
    .replace(/ *\r?\n */g, '\n')
    .replace(/\n{3,}/g, '\n\n');
  await send(text);
}

function itemsOf(context) {
  return String(context.arguments.items || '').split(/[|\n]/).map(item => item.trim()).filter(Boolean);
}

export async function checklist(context) {
  const items = itemsOf(context);
  if (!items.length || items.length > 50) {
    await ui.notify('Укажите от 1 до 50 пунктов через |');
    return;
  }
  await send(items.map(item => '☐ ' + item).join('\n'));
}

export async function choose(context) {
  const items = itemsOf(context);
  if (items.length < 2 || items.length > 30) {
    await ui.notify('Укажите от 2 до 30 вариантов через |');
    return;
  }
  await send('Выбор: ' + items[Math.floor(Math.random() * items.length)]);
}
