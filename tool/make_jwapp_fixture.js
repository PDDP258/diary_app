#!/usr/bin/env node
/**
 * 从本地采集的原始教务响应生成「脱敏 fixture」，供 Dart 单测使用。
 *
 * 输入（.capture/ 已在 .gitignore 中，绝不进仓库）：
 *   .capture/kb_api.json     — 课表接口 cxxszhxqkb.do 的完整响应
 *   .capture/api_extra.txt   — 多接口响应拼接（含 cxjcs.do 学期配置）
 *
 * 输出（进仓库，会被反复重跑覆盖）：
 *   test/fixtures/jwapp/courses_2026-2027-1.json
 *   test/fixtures/jwapp/semesters.json
 *
 * 脱敏范围：只替换个人标识（学号 XH / 姓名 XM）。
 * 课程名、教师名、教室、班级属课表页面公开信息，保留以维持测试语义
 * （中文长度、【本】前缀、逗号分隔教师等）。
 *
 * 用法：node tool/make_jwapp_fixture.js
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CAPTURE = path.join(ROOT, '.capture');
const OUT_DIR = path.join(ROOT, 'test', 'fixtures', 'jwapp');

const MASK = { XH: '2023000000', XM: '示例同学' };
// 学期配置**必须保留全部行**。曾经只保留最新 12 条，恰好把末尾一条 `PX: null`
// 的毒行截掉了，于是「当前学期选错 → 0 课 + 开学日错」的 bug 在单测里完全
// 看不出来。fixture 要忠实于真实响应，别为了体积做有损裁剪。

function maskRows(rows) {
  return rows.map((row) => {
    const out = { ...row };
    for (const key of Object.keys(MASK)) {
      if (key in out && out[key] !== null && out[key] !== undefined) {
        out[key] = MASK[key];
      }
    }
    return out;
  });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** api_extra.txt 的分段格式：`### 名称\n[状态码] {json}`，段间以 ======== 分隔 */
function readExtraSection(file, name) {
  const raw = fs.readFileSync(file, 'utf8');
  for (const chunk of raw.split('========')) {
    const m = chunk.match(/^###\s*(\S+)[^\n]*\n\[(\d+)\]\s*([\s\S]*)$/);
    if (!m) continue;
    if (m[1] !== name) continue;
    if (m[2] !== '200') throw new Error(`${name} 返回状态码 ${m[2]}，采集无效`);
    return JSON.parse(m[3]);
  }
  throw new Error(`api_extra.txt 中未找到 ${name} 段`);
}

function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });

  // ---- 课表 ----
  const kb = readJson(path.join(CAPTURE, 'kb_api.json'));
  const kbTable = kb.datas.cxxszhxqkb;
  const coursesOut = {
    _comment:
      'jwapp 课表接口 (cxxszhxqkb.do) 真实响应，已脱敏 XH/XM。' +
      '请勿手工编辑结构，用 tool/make_jwapp_fixture.js 重新生成。',
    code: kb.code,
    datas: {
      cxxszhxqkb: { ...kbTable, rows: maskRows(kbTable.rows) },
    },
  };
  const coursesFile = path.join(OUT_DIR, 'courses_2026-2027-1.json');
  fs.writeFileSync(coursesFile, JSON.stringify(coursesOut, null, 2), 'utf8');

  // ---- 学期配置 ----
  const sem = readExtraSection(path.join(CAPTURE, 'api_extra.txt'), 'cxjcs.do');
  const semTable = sem.datas.cxjcs;
  const semOut = {
    _comment:
      'jwapp 学期配置接口 (cxjcs.do) 真实响应，仅保留最新若干条。' +
      '请勿手工编辑结构，用 tool/make_jwapp_fixture.js 重新生成。',
    code: sem.code,
    datas: {
      cxjcs: { ...semTable },
    },
  };
  const semFile = path.join(OUT_DIR, 'semesters.json');
  fs.writeFileSync(semFile, JSON.stringify(semOut, null, 2), 'utf8');

  // ---- 自检：确认原始个人标识没有以任何形式残留 ----
  const originalValues = new Set();
  for (const row of kbTable.rows) {
    for (const key of Object.keys(MASK)) {
      const v = row[key];
      if (v !== null && v !== undefined && String(v).trim() !== '') {
        originalValues.add(String(v));
      }
    }
  }
  const written = fs.readFileSync(coursesFile, 'utf8') + fs.readFileSync(semFile, 'utf8');
  const leaks = [...originalValues].filter((v) => written.includes(v));
  if (leaks.length) {
    throw new Error(`脱敏失败，仍含原始个人标识：${leaks.join(', ')}`);
  }

  console.log(`课程 fixture : ${coursesFile}`);
  console.log(`  记录数     : ${coursesOut.datas.cxxszhxqkb.rows.length}`);
  console.log(`学期 fixture : ${semFile}`);
  console.log(`  学期数     : ${semOut.datas.cxjcs.rows.length}（全部保留）`);
  console.log('脱敏校验通过：无原始个人标识残留');
}

main();
