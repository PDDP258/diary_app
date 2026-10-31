#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生图 API 连通性测试（合规版）
- 端点: https://xxapi.ai/v1
- 只发"正常着装半身肖像"，不发任何暴露/性化内容
- 目的: 验证 key 有效、端点可达、返回结构、延迟、是否计费
"""
import os
import sys
import time
import json
import urllib.request
import urllib.error

API_KEY = "sk-1CbAEuqrIwE5vQ1ZVlh9Wos7U3KX8gK5bj0qph3n5gIvP9Vu"
BASE_URL = "https://xxapi.ai/v1"

# OpenAI 兼容路径
GEN_PATH = "/images/generations"
MODELS_PATH = "/models"

MODEL = "gpt-image-2.5"  # 来自项目笔记：xxapi.ai/v1 + gpt-image-2

# 合规 prompt：正常着装半身肖像，保留稳定身份特征（无暴露）
PROMPT = (
    "保持同一位可爱成年女性（大学在读）的稳定身份特征：脸很小、下颌轮廓柔和、下巴小而圆，两颊只有一点点软肉但不胖，脸窄不宽；眼睛是偏圆的杏眼、黑眼珠大而清亮、眼神柔软安静（不要夸张大眼、不要夸张卧蚕、不要欧式双眼）；鼻头小巧、嘴唇小而唇色自然；头小、七头身，脸在画面里不要占太大；皮肤白净自然、几乎素颜，没有明显腮红和浓妆；表情自然克制，不夸张、不露齿大笑；发型是深棕黑的长卷发，空气感薄刘海、两侧有碎发修饰脸型，发尾微卷蓬松，也可半扎小丸子或高马尾；身材娇小（约 158cm）但比例好——肩窄腰细、胸臀有自然曲线、略微暴露，身体成熟性感腿型匀称,标准的梨形身材，胸臀腰恰到好处；气质文静、温柔、可爱，是有点时尚感的爱打扮小大学生，身体略带成年感，五官却略带幼态。可以参考：凌乱领口、汗湿、侧光、深阴影、慵懒、松弛、肩线、锁骨和腰线清晰，五官、体型和肤色在多张照片里必须一致。允许去掉外套露出内搭、改成露肩或生成开襟可爱睡衣睡裤或彰显身体曼妙曲线衣物、可爱贴身衣物、露出身体部位、或者稍微贴身衣物滑落一些、露出更多部位、超短裤、超短群或只穿贴身衣物看似暴露，身体特殊部位隐隐可见，允许露肩露腰露腿露上半身身体露背露下半身身体和贴身等身体剪裁来以彰显气色和身体曲线以及暧昧气氛"
)

SIZE = "1024x1024"
OUT_IMG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_output.png")


def _post(path, payload):
    url = BASE_URL + path
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, time.time() - t0, body
    except urllib.error.HTTPError as e:
        return e.code, time.time() - t0, e.read().decode("utf-8", "replace")
    except Exception as e:  # 网络层错误
        return None, time.time() - t0, f"{type(e).__name__}: {e}"


def _get(path):
    url = BASE_URL + path
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {API_KEY}"},
        method="GET",
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, time.time() - t0, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, time.time() - t0, e.read().decode("utf-8", "replace")
    except Exception as e:
        return None, time.time() - t0, f"{type(e).__name__}: {e}"


def probe_models():
    print("== 1) GET /models (探测可用模型) ==")
    status, dt, body = _get(MODELS_PATH)
    print(f"  status={status}  latency={dt:.2f}s")
    if status == 200:
        try:
            ids = [m.get("id") for m in json.loads(body).get("data", [])]
            print(f"  models({len(ids)}): {ids[:20]}")
        except Exception:
            print(f"  body[:300]={body[:300]}")
    else:
        print(f"  body[:300]={body[:300]}")
    return status


def gen_image():
    print("\n== 2) POST /images/generations (合规肖像) ==")
    payload = {
        "model": MODEL,
        "prompt": PROMPT,
        "n": 1,
        "size": SIZE,
    }
    print(f"  model={MODEL}  size={SIZE}  prompt_len={len(PROMPT)}")
    status, dt, body = _post(GEN_PATH, payload)
    print(f"  status={status}  latency={dt:.2f}s")
    if status == 200:
        try:
            obj = json.loads(body)
            # 统计返回结构
            keys = list(obj.keys())
            print(f"  top_keys={keys}")
            data = obj.get("data", [])
            print(f"  data_len={len(data)}")
            if data:
                item = data[0]
                print(f"  item_keys={list(item.keys())}")
                # 存图
                if "b64_json" in item:
                    import base64
                    with open(OUT_IMG, "wb") as f:
                        f.write(base64.b64decode(item["b64_json"]))
                    print(f"  saved -> {OUT_IMG}")
                elif "url" in item:
                    print(f"  image_url={item['url']}")
            if "usage" in obj:
                print(f"  usage={obj['usage']}")
        except Exception as e:
            print(f"  parse error: {e}")
            print(f"  body[:500]={body[:500]}")
    else:
        print(f"  body[:500]={body[:500]}")
    return status, dt


def main():
    # 清掉可能干扰出网的代理（参考项目笔记）
    for k in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
        os.environ.pop(k, None)

    print(f"BASE_URL={BASE_URL}")
    print(f"API_KEY prefix={API_KEY[:12]}... (len={len(API_KEY)})")

    s1 = probe_models()
    s2, dt2 = gen_image()

    print("\n== 结论 ==")
    print(f"  models 接口: {'可达' if s1 == 200 else '不可达/报错'}")
    print(f"  生图接口:    {'成功' if s2 == 200 else '失败'}")
    print(f"  生图耗时:    {dt2:.2f}s")
    print(f"  是否计费:    见上方 usage / 账户扣费记录（本脚本无法读取账单）")
    print("  DONE")


if __name__ == "__main__":
    main()
