#!/usr/bin/env node
// CDP 只读调试客户端 —— 连接已用 --remote-debugging-port 启动的浏览器，读取页面内容。
// 用途：用户在自己的浏览器里手动登录教务系统，这里只读取 DOM（不碰账号密码）。
//
// 用法：
//   node tool/cdp.js list                     列出所有页面
//   node tool/cdp.js text [url/title 子串]     输出页面可见文本
//   node tool/cdp.js html [url/title 子串]     输出完整 outerHTML
//   node tool/cdp.js eval "<js 表达式>" [子串]  执行任意表达式并取值
//   node tool/cdp.js savedir <目录>            把所有页面的 html/text 落盘（采集用）
//
// 环境变量 CDP_PORT 可改端口，默认 9222。

const PORT = process.env.CDP_PORT || 9222;
const BASE = `http://127.0.0.1:${PORT}`;

async function listTargets() {
  const res = await fetch(`${BASE}/json/list`);
  if (!res.ok) throw new Error(`CDP 返回 ${res.status}，浏览器没起来或端口不对`);
  return res.json();
}

function pages(targets, filter) {
  let out = targets.filter((t) => t.type === 'page');
  if (filter) out = out.filter((t) => `${t.url}${t.title}`.includes(filter));
  return out;
}

function evaluate(wsUrl, expression, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => {
      try { ws.close(); } catch (_) {}
      reject(new Error('CDP 求值超时'));
    }, timeoutMs);

    ws.onopen = () => {
      ws.send(JSON.stringify({
        id: 1,
        method: 'Runtime.evaluate',
        params: { expression, returnByValue: true, awaitPromise: true },
      }));
    };

    ws.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (_) { return; }
      if (msg.id !== 1) return;
      clearTimeout(timer);
      try { ws.close(); } catch (_) {}
      if (msg.error) return reject(new Error(JSON.stringify(msg.error)));
      const r = msg.result || {};
      if (r.exceptionDetails) {
        const d = r.exceptionDetails;
        return reject(new Error(`${d.text} ${d.exception?.description || ''}`.trim()));
      }
      resolve(r.result ? r.result.value : undefined);
    };

    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error('CDP WebSocket 连接失败'));
    };
  });
}

/// 监听一段时间内的网络请求（可先 reload 页面触发），返回 XHR/Fetch/Document 的行描述。
function recordNetwork(wsUrl, seconds, doReload) {
  return new Promise((resolve) => {
    const ws = new WebSocket(wsUrl);
    const out = [];
    const offline = 2500;

    const finish = () => {
      clearTimeout(timer);
      try { ws.close(); } catch (_) {}
      resolve(out);
    };

    const timer = setTimeout(finish, seconds * 1000);

    ws.onopen = () => {
      ws.send(JSON.stringify({ id: 1, method: 'Page.enable' }));
      ws.send(JSON.stringify({ id: 2, method: 'Network.enable' }));
      if (doReload) {
        setTimeout(() => {
          ws.send(JSON.stringify({
            id: 3,
            method: 'Page.reload',
            params: { ignoreCache: false },
          }));
        }, 600);
      }
    };

    ws.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (_) { return; }
      if (msg.method !== 'Network.requestWillBeSent') return;
      const { request, type, requestId } = msg.params;
      if (!['XHR', 'Fetch', 'Document'].includes(type)) return;
      if (/\.(png|jpe?g|gif|svg|css|woff2?|ttf|ico)$/i.test(request.url)) return;

      const parts = [`${requestId.slice(-6)} ${request.method} [${type}] ${request.url}`];
      if (request.postData) parts.push(`      POST: ${String(request.postData).slice(0, 600)}`);
      out.push(parts.join('\n'));
    };

    ws.onerror = finish;
  });
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const targets = await listTargets();

  if (!cmd || cmd === 'list') {
    const ps = pages(targets);
    if (!ps.length) console.log('（没有页面）');
    for (const p of ps) console.log(`${p.id}\t${p.title}\t${p.url}`);
    return;
  }

  if (cmd === 'net') {
    let seconds = 15;
    let doReload = false;
    let filter;
    for (const a of rest) {
      if (a === 'reload') doReload = true;
      else if (/^\d+$/.test(a)) seconds = Number(a);
      else filter = a;
    }
    const ps = pages(targets, filter);
    if (!ps.length) throw new Error('没有匹配的页面');
    const page = ps[ps.length - 1];
    const lines = await recordNetwork(page.webSocketDebuggerUrl, seconds, doReload);
    if (!lines.length) console.log('（这段时间内没有捕获到请求）');
    for (const l of lines) console.log(l);
    return;
  }

  if (cmd === 'savedir') {
    const dir = rest[0];
    if (!dir) throw new Error('savedir 需要一个目录');
    const fs = await import('node:fs/promises');
    const path = await import('node:path');
    await fs.mkdir(dir, { recursive: true });
    const ps = pages(targets);
    let n = 0;
    for (const p of ps) {
      if (!/^https?:/.test(p.url)) continue;
      const stamp = String(++n).padStart(2, '0');
      const base = path.join(dir, `${stamp}_${p.title.replace(/[\\/:*?"<>|]/g, '_').slice(0, 40) || 'page'}`);
      try {
        const html = await evaluate(p.webSocketDebuggerUrl, 'document.documentElement.outerHTML');
        await fs.writeFile(`${base}.html`, html ?? '', 'utf8');
        const text = await evaluate(p.webSocketDebuggerUrl, 'document.body ? document.body.innerText : ""');
        await fs.writeFile(`${base}.txt`, text ?? '', 'utf8');
        console.log(`已保存 ${base}.html / .txt  ← ${p.url}`);
      } catch (e) {
        console.log(`跳过 ${p.url}：${e.message}`);
      }
    }
    return;
  }

  let expr;
  let filter;
  if (cmd === 'html') { expr = 'document.documentElement.outerHTML'; filter = rest[0]; }
  else if (cmd === 'text') { expr = 'document.body ? document.body.innerText : ""'; filter = rest[0]; }
  else if (cmd === 'eval') { expr = rest[0]; filter = rest[1]; }
  else throw new Error(`未知命令: ${cmd}`);

  const ps = pages(targets, filter);
  if (!ps.length) throw new Error('没有匹配的页面');
  const page = ps[ps.length - 1];
  const out = await evaluate(page.webSocketDebuggerUrl, expr);
  console.log(typeof out === 'string' ? out : JSON.stringify(out, null, 2));
}

main().catch((e) => {
  console.error(`错误：${e.message}`);
  process.exit(1);
});
