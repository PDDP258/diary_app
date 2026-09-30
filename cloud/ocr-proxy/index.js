'use strict';
/**
 * 小记日记 · 课表图片识别中转云函数（腾讯云 SCF）
 *
 * 存在意义：SecretId/SecretKey 绝不能打进 APK。App 只调用本函数的 URL，
 * 由云函数持有密钥去调腾讯云「表格识别(V3)」RecognizeTableAccurateOCR。
 *
 * 入参（二选一，均为 JSON body）：
 *   { "image": "<picture base64，可带 data:image/jpeg;base64, 前缀>" }
 *   { "imageUrl": "https://..." }
 *   { "appKey": "<与函数环境变量 APP_KEY 一致时通过校验>" }  —— 也可放请求头 X-App-Key
 *
 * 出参（已归一化，Dart 侧 OcrResult.fromJson 直接吃）：
 *   {
 *     "ok": true,
 *     "angle": 0.0,
 *     "requestId": "...",
 *     "tables": [
 *       { "index": 0, "type": 1, "rows": 12, "cols": 8,
 *         "cells": [ { "r": 0, "c": 1, "rs": 1, "cs": 1, "text": "高等数学", "confidence": 99.1 } ] }
 *     ]
 *   }
 *   失败：{ "ok": false, "error": "人话错误信息", "code": "..." }
 *
 * 单元换算说明：腾讯云返回 RowTl/ColTl/RowBr/ColBr 为「左上闭、右下开」的
 * 索引区间（官方示例：标题格 ColTl=0, RowTl=0, ColBr=9, RowBr=1 表示跨 0..8 列）。
 * 故 rs = RowBr - RowTl，cs = ColBr - ColTl，最小钳到 1。
 */

// 懒加载：本地单测 normalize 时无需安装 SDK
let _OcrClientCtor = null;

// 单张图片 base64 上限（腾讯云接口限 10M；SCF 请求体也有上限，留出余量）
const MAX_BASE64_LEN = 8 * 1024 * 1024;

function respond(statusCode, payload) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type,X-App-Key',
      'Access-Control-Allow-Methods': 'POST,OPTIONS',
    },
    body: JSON.stringify(payload),
  };
}

/** 兼容 SCF 函数 URL / API 网关 / 直接事件调用三种形态 */
function readBody(event) {
  if (!event) return {};
  if (typeof event === 'string') {
    try { return JSON.parse(event); } catch (e) { return {}; }
  }
  // 函数 URL：{ body: "<json string>", isBase64Encoded: bool }
  if (typeof event.body === 'string') {
    const raw = event.isBase64Encoded
      ? Buffer.from(event.body, 'base64').toString('utf8')
      : event.body;
    try { return JSON.parse(raw); } catch (e) { return {}; }
  }
  if (typeof event.body === 'object' && event.body !== null) return event.body;
  return event; // 控制台直接测试时传的就是业务参数
}

function readAppKey(event, body) {
  const h = (event && event.headers) || {};
  const lower = {};
  for (const k of Object.keys(h)) lower[k.toLowerCase()] = h[k];
  return body.appKey || lower['x-app-key'] || '';
}

function stripDataUrl(s) {
  const idx = s.indexOf('base64,');
  return idx >= 0 ? s.slice(idx + 7) : s;
}

function buildClient() {
  const secretId =
    process.env.OCR_SECRET_ID || process.env.TENCENTCLOUD_SECRETID;
  const secretKey =
    process.env.OCR_SECRET_KEY || process.env.TENCENTCLOUD_SECRETKEY;
  const token = process.env.TENCENTCLOUD_SESSIONTOKEN;
  if (!secretId || !secretKey) {
    const err = new Error(
      '云函数缺少密钥：请为函数配置「运行角色」（自动注入临时密钥），' +
        '或设置环境变量 OCR_SECRET_ID / OCR_SECRET_KEY'
    );
    err.code = 'NO_CREDENTIAL';
    throw err;
  }
  if (!_OcrClientCtor) {
    const tencentcloud = require('tencentcloud-sdk-nodejs-ocr');
    _OcrClientCtor = tencentcloud.ocr.v20181119.Client;
  }
  return new _OcrClientCtor({
    credential: { secretId, secretKey, token },
    region: process.env.TENCENTCLOUD_REGION || 'ap-guangzhou',
    profile: {
      httpProfile: { endpoint: 'ocr.tencentcloudapi.com', reqTimeout: 25 },
    },
  });
}

/** 腾讯云原始响应 → 归一化结构 */
function normalize(tencentResponse) {
  const detections = (tencentResponse && tencentResponse.TableDetections) || [];
  const tables = [];
  for (let i = 0; i < detections.length; i++) {
    const det = detections[i] || {};
    const rawCells = det.Cells || [];
    if (!rawCells.length) continue;

    const cells = [];
    let maxRow = 0;
    let maxCol = 0;
    for (const cell of rawCells) {
      const text = (cell.Text || '').trim();
      if (!text) continue;
      const r = Number.isFinite(cell.RowTl) ? cell.RowTl : 0;
      const c = Number.isFinite(cell.ColTl) ? cell.ColTl : 0;
      const rEnd = Number.isFinite(cell.RowBr) ? cell.RowBr : r + 1;
      const cEnd = Number.isFinite(cell.ColBr) ? cell.ColBr : c + 1;
      const rs = Math.max(1, rEnd - r);
      const cs = Math.max(1, cEnd - c);
      cells.push({
        r: r,
        c: c,
        rs: rs,
        cs: cs,
        text: text,
        confidence:
          typeof cell.Confidence === 'number'
            ? Math.round(cell.Confidence * 10) / 10
            : null,
      });
      maxRow = Math.max(maxRow, r + rs);
      maxCol = Math.max(maxCol, c + cs);
    }
    if (!cells.length) continue;

    tables.push({
      index: tables.length,
      sourceIndex: i,
      type: typeof det.Type === 'number' ? det.Type : 0,
      rows: maxRow,
      cols: maxCol,
      coord: det.TableCoordPoint || null,
      cells: cells,
    });
  }
  return {
    ok: true,
    angle: typeof tencentResponse?.Angle === 'number' ? tencentResponse.Angle : 0,
    requestId: tencentResponse?.RequestId || null,
    tables: tables,
  };
}

/** 供本地单测引用（SCF 运行时不使用） */
exports._normalize = normalize;

exports.main_handler = async (event) => {
  try {
    if (event && event.requestContext && event.requestContext.http) {
      // 函数 URL 的 CORS 预检
      const method = event.requestContext.http.method;
      if (method === 'OPTIONS') return respond(204, {});
      if (method !== 'POST' && method !== 'GET') {
        return respond(405, { ok: false, error: '仅支持 POST' });
      }
    }

    const expectedKey = process.env.APP_KEY;
    const body = readBody(event);
    if (expectedKey && readAppKey(event, body) !== expectedKey) {
      return respond(401, { ok: false, code: 'BAD_APP_KEY', error: '应用密钥不正确' });
    }

    let imageBase64 = body.image || body.imageBase64 || '';
    const imageUrl = body.imageUrl || '';
    if (!imageBase64 && !imageUrl) {
      return respond(400, {
        ok: false,
        code: 'NO_IMAGE',
        error: '缺少 image（base64）或 imageUrl',
      });
    }
    if (imageBase64) {
      imageBase64 = stripDataUrl(String(imageBase64)).replace(/\s/g, '');
      if (imageBase64.length > MAX_BASE64_LEN) {
        return respond(413, {
          ok: false,
          code: 'IMAGE_TOO_LARGE',
          error: '图片过大，请在客户端压缩后重试',
        });
      }
    }

    const client = buildClient();
    const params = { UseNewModel: true };
    if (imageUrl) {
      params.ImageUrl = imageUrl;
    } else {
      params.ImageBase64 = imageBase64;
    }

    const res = await client.RecognizeTableAccurateOCR(params);
    const normalized = normalize(res);
    if (!normalized.tables.length) {
      return respond(200, {
        ok: false,
        code: 'NO_TABLE',
        requestId: normalized.requestId,
        error: '没在图片里找到表格，换一张更清晰、边框完整的课表截图试试',
        tables: [],
      });
    }
    return respond(200, normalized);
  } catch (err) {
    const code = err && err.code ? String(err.code) : 'INTERNAL';
    let message = (err && err.message) || '识别服务异常';
    if (code.startsWith('AuthFailure')) {
      message = '云函数密钥无效或未授权 OCR 服务';
    } else if (code === 'FailedOperation.ImageDecodeFailed') {
      message = '图片无法解码，请换一张图片';
    } else if (code === 'RequestLimitExceeded') {
      message = '识别请求过于频繁，请稍后重试';
    } else if (code === 'ResourceUnavailable.InArrears' || code === 'FailedOperation.OcrResourceNotEnough') {
      message = '识别额度已用尽或账号欠费';
    }
    console.error('[ocr-proxy] error', code, err);
    return respond(500, { ok: false, code, error: message });
  }
};
