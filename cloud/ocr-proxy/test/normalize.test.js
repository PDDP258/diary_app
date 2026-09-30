'use strict';
/**
 * 归一化逻辑单测（不依赖腾讯云 SDK）
 *   node --test cloud/ocr-proxy/test/
 *
 * 用腾讯云官方文档的返回示例做 fixture，锁定「左上闭/右下开」的档位换算。
 */

const test = require('node:test');
const assert = require('node:assert');
const { _normalize } = require('../index.js');

// 摘自腾讯云官方响应示例（含跨列标题格）
const officialSample = {
  TableDetections: [
    {
      Cells: [
        {
          ColTl: 0,
          RowTl: 0,
          ColBr: 9,
          RowBr: 1,
          Text: '五(1) 班卫生值日表',
          Type: 'body',
          Confidence: 99.98,
        },
        {
          ColTl: 0,
          RowTl: 1,
          ColBr: 1,
          RowBr: 2,
          Text: '星期一',
          Type: 'body',
          Confidence: 99.96,
        },
        {
          ColTl: 1,
          RowTl: 1,
          ColBr: 2,
          RowBr: 2,
          Text: '梅亚婷',
          Type: 'body',
          Confidence: 99.99,
        },
      ],
      Type: 1,
      TableCoordPoint: [
        { X: 50, Y: 100 },
        { X: 800, Y: 100 },
      ],
    },
  ],
  Angle: 0.0,
  RequestId: 'req-abc',
};

test('跨列标题格换算为 cs=9（右下开区间）', () => {
  const out = _normalize(officialSample);
  assert.strictEqual(out.ok, true);
  const title = out.tables[0].cells[0];
  assert.deepStrictEqual(
    { r: title.r, c: title.c, rs: title.rs, cs: title.cs, text: title.text },
    { r: 0, c: 0, rs: 1, cs: 9, text: '五(1) 班卫生值日表' }
  );
});

test('单格 rs/cs 为 1', () => {
  const out = _normalize(officialSample);
  const c = out.tables[0].cells[2];
  assert.strictEqual(c.rs, 1);
  assert.strictEqual(c.cs, 1);
  assert.strictEqual(c.text, '梅亚婷');
});

test('表格尺寸取所有单元格的最大边界', () => {
  const out = _normalize(officialSample);
  assert.strictEqual(out.tables[0].rows, 2);
  assert.strictEqual(out.tables[0].cols, 9);
});

test('空文本单元格被丢弃，空表格不进结果', () => {
  const out = _normalize({
    TableDetections: [{ Cells: [{ RowTl: 0, ColTl: 0, RowBr: 1, ColBr: 1, Text: '  ' }] }],
  });
  assert.strictEqual(out.tables.length, 0);
});

test('缺少行列表述时按 1 格兜底，不产生 0 跨度的僵尸格', () => {
  const out = _normalize({
    TableDetections: [{ Cells: [{ Text: '高等数学' }], Type: 1 }],
  });
  const c = out.tables[0].cells[0];
  assert.strictEqual(c.rs, 1);
  assert.strictEqual(c.cs, 1);
  assert.strictEqual(out.tables[0].rows, 1);
  assert.strictEqual(out.tables[0].cols, 1);
});

test('置信度保留一位小数，缺失则为 null', () => {
  const out = _normalize({
    TableDetections: [
      {
        Cells: [
          { RowTl: 0, ColTl: 0, RowBr: 1, ColBr: 1, Text: 'A', Confidence: 95.678 },
          { RowTl: 0, ColTl: 1, RowBr: 1, ColBr: 2, Text: 'B' },
        ],
      },
    ],
  });
  assert.strictEqual(out.tables[0].cells[0].confidence, 95.7);
  assert.strictEqual(out.tables[0].cells[1].confidence, null);
});

test('无表格时 tables 为空且 ok 仍为 true（由上层判空）', () => {
  const out = _normalize({});
  assert.strictEqual(out.ok, true);
  assert.deepStrictEqual(out.tables, []);
});
