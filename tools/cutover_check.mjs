#!/usr/bin/env node
// Pre-deploy gate:  node tools/cutover_check.mjs            (production config: expects the real publishable key + syncEnabled:true)
//                   node tools/cutover_check.mjs --staged   (before the flip: key present, syncEnabled may still be false)
import fs from 'node:fs'; import vm from 'node:vm'; import { execSync } from 'node:child_process';
const staged = process.argv.includes('--staged'); let bad = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) bad++; };
const cfgSrc = fs.readFileSync('config.js', 'utf8'), ctx = { window: {} }; vm.runInNewContext(cfgSrc, ctx); const c = ctx.window.SUPABASE_CONFIG || {};
ok(c.url === 'https://oxqcprgreelxfjhlqpxl.supabase.co', 'config.js url is the hosted project');
ok(/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(c.publishableKey || ''), 'config.js has a real sb_publishable_ key (not the placeholder)');
ok(!/sb_secret_|service_role|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/.test(cfgSrc.replace(/^\s*\/\/.*$/gm, '')), 'config.js contains no secret / service_role / JWT-looking value');
ok(staged ? true : c.syncEnabled === true, staged ? '(staged) syncEnabled not checked' : 'config.js syncEnabled is true');
const html = fs.readFileSync('index.html', 'utf8');
ok(/supabase-js@2\.\d+\.\d+\/dist\/umd\/supabase\.js"[^>]*integrity="sha384-/.test(html), 'supabase-js is pinned with an SRI hash');
ok(/data\/plan-data\.js\?v=\d+/.test(html), 'plan-data.js is cache-busted');
const plan = fs.readFileSync('data/plan-data.js', 'utf8'); ok(/"version":3\b/.test(plan) && plan.includes('"id":"v2-w1-d1"') && !/"name":"(Whole egg|Cooked)/.test(plan), 'bundled plan is the empty 28-day plan (v3, same day ids)');
const vj = fs.readFileSync('vercel.json', 'utf8'); ok(vj.includes('https://oxqcprgreelxfjhlqpxl.supabase.co') && !vj.includes('unsafe-eval'), 'CSP allows only the hosted Supabase origin (no unsafe-eval)');
const js = html.split(/<script>/).slice(1).map(x => x.split('</script>')[0]).join('\n;\n'); try { new vm.Script(js); ok(true, 'inline app script parses'); } catch (e) { ok(false, 'inline app script parses: ' + e.message); }
for (const f of ['config.local.js', 'config.local.hosted.js']) { let tracked = ''; try { tracked = execSync(`git ls-files ${f}`, { encoding: 'utf8' }).trim(); } catch {} ok(!tracked, `${f} is not tracked by git`); }
const files = execSync('git ls-files', { encoding: 'utf8' }).split('\n').filter(Boolean).concat(['sync-core.js','tools/cutover_check.mjs']); let leak = [];
for (const f of files) { if (!fs.existsSync(f) || /\.(png|jpg|pdf)$/i.test(f) || f.endsWith('cutover_check.mjs')) continue; const t = fs.readFileSync(f, 'utf8'); if (/sb_secret_[A-Za-z0-9_-]{16,}/.test(t)) leak.push(f); }
ok(!leak.length, 'no sb_secret_ key in tracked files' + (leak.length ? ': ' + leak.join(',') : ''));
console.log(bad ? `\n${bad} check(s) failed - do NOT deploy yet.` : '\nAll checks passed.'); process.exit(bad ? 1 : 0);
