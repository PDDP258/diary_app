import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:diary_app/models/course.dart';
import 'package:diary_app/services/course_import/ocr/course_cell_parser.dart';
import 'package:diary_app/services/course_import/ocr/ocr_client.dart';
import 'package:diary_app/services/course_import/ocr/ocr_grid.dart';
import 'package:diary_app/services/course_import/ocr/ocr_models.dart';
import 'package:diary_app/services/course_import/ocr/ocr_pipeline.dart';

void main() {
  // ===================== 1. 结果解析 =====================

  group('OcrResult.fromJson', () {
    test('解析云函数归一化结构', () {
      final result = OcrResult.fromJson({
        'ok': true,
        'angle': 0.0,
        'tables': [
          {
            'type': 1,
            'rows': 2,
            'cols': 9,
            'cells': [
              {'r': 0, 'c': 0, 'rs': 1, 'cs': 9, 'text': '课表', 'confidence': 99.1},
              {'r': 1, 'c': 1, 'rs': 1, 'cs': 1, 'text': '高等数学'},
            ],
          }
        ],
      });
      expect(result.tables, hasLength(1));
      expect(result.tables.first.cells.first.colSpan, 9);
      expect(result.tables.first.cells[1].text, '高等数学');
    });

    test('解析腾讯云原始结构（Response.TableDetections + 开区间 Br）', () {
      final result = OcrResult.fromJson({
        'Response': {
          'TableDetections': [
            {
              'Cells': [
                {'ColTl': 0, 'RowTl': 0, 'ColBr': 9, 'RowBr': 1, 'Text': '标题'},
                {'ColTl': 1, 'RowTl': 1, 'ColBr': 2, 'RowBr': 2, 'Text': '梅亚婷'},
              ],
              'Type': 1,
            }
          ],
          'Angle': -1.5,
          'RequestId': 'abc',
        }
      });
      final cell = result.tables.first.cells.first;
      expect(cell.colSpan, 9);
      expect(cell.rowSpan, 1);
      expect(cell.text, '标题');
      expect(result.angle, -1.5);
      expect(result.requestId, 'abc');
    });

    test('空文本单元格与空表被丢弃', () {
      final result = OcrResult.fromJson({
        'ok': true,
        'tables': [
          {
            'cells': [
              {'r': 0, 'c': 0, 'text': '   '},
            ]
          }
        ],
      });
      expect(result.tables, isEmpty);
      expect(result.isEmpty, isTrue);
    });

    test('ok=false 时抛 OcrException 并带上服务端文案', () {
      expect(
        () => OcrResult.fromJson({
          'ok': false,
          'code': 'NO_TABLE',
          'error': '没在图片里找到表格',
        }),
        throwsA(isA<OcrException>()
            .having((e) => e.message, 'message', '没在图片里找到表格')
            .having((e) => e.code, 'code', 'NO_TABLE')),
      );
    });
  });

  // ===================== 2. 网格还原 =====================

  group('OcrGrid.fromTable', () {
    test('合并单元格覆盖到的每个位置都能取到同一文本', () {
      final grid = OcrGrid.fromTable(OcrTable(cells: [
        const OcrCell(row: 0, col: 1, rowSpan: 2, colSpan: 1, text: '高等数学'),
        const OcrCell(row: 0, col: 2, text: '线性代数'),
      ]));
      // 坐标按最小行列平移，网格尺寸是相对跨度（2 行 × 2 列）
      expect(grid.rows, 2);
      expect(grid.cols, 2);
      expect(grid.at(0, 0), '高等数学');
      expect(grid.at(1, 0), '高等数学');
      expect(grid.at(0, 1), '线性代数');
      expect(grid.at(1, 1), isNull);
    });

    test('1 基坐标会被平移到 0 基，网格不会多出空行空列', () {
      final grid = OcrGrid.fromTable(OcrTable(cells: [
        const OcrCell(row: 1, col: 1, text: 'A'),
        const OcrCell(row: 2, col: 2, text: 'B'),
      ]));
      expect(grid.rowOffset, 1);
      expect(grid.colOffset, 1);
      expect(grid.rows, 2);
      expect(grid.cols, 2);
      expect(grid.at(0, 0), 'A');
      expect(grid.at(1, 1), 'B');
    });

    test('空表得到空网格', () {
      final grid = OcrGrid.fromTable(const OcrTable(cells: []));
      expect(grid.isEmpty, isTrue);
    });
  });

  // ===================== 3. 表头与节次定位 =====================

  group('ScheduleGridParser', () {
    test('识别星期行、节次列与每行节次区间', () {
      final result = ScheduleGridParser.parse(OcrGrid.fromTable(_scheduleTable()));
      expect(result.header.dayDetected, isTrue);
      expect(result.header.dayHeaderRow, 0);
      expect(result.header.sectionColumn, 0);
      expect(result.header.bodyTopRow, 1);
      expect(result.header.rowSlots[1]!.start, 1);
      expect(result.header.rowSlots[1]!.end, 1);
      expect(result.header.rowSlots[6]!.start, 6);
      expect(result.header.rowSlots[6]!.end, 6);
    });

    test('课程格按网格位置得到星期与节次跨度', () {
      final result = ScheduleGridParser.parse(OcrGrid.fromTable(_scheduleTable()));
      final math = result.courses.firstWhere((c) => c.text.contains('高等数学'));
      expect(math.dayOfWeek, 1);
      expect(math.startSection, 1);
      expect(math.endSection, 2);
      expect(math.rowCount, 2);

      final english = result.courses.firstWhere((c) => c.text.contains('大学英语'));
      expect(english.dayOfWeek, 2);
      expect(english.startSection, 3);
      expect(english.endSection, 4);
    });

    test('只有一行的课程格按单节处理，不沿用合并节次标签', () {
      final table = OcrTable(cells: [
        ..._dayHeader(),
        // 节次标签「1-2节」纵向合并两行
        const OcrCell(row: 1, col: 0, rowSpan: 2, text: '1-2节'),
        // 课程只占第一行
        const OcrCell(row: 1, col: 1, text: '高等数学'),
      ]);
      final result = ScheduleGridParser.parse(OcrGrid.fromTable(table));
      final c = result.courses.single;
      expect(c.startSection, 1);
      expect(c.endSection, 1);
    });

    test('节次标签是纯时间时退回行序编号', () {
      final table = OcrTable(cells: [
        ..._dayHeader(),
        const OcrCell(row: 1, col: 0, text: '08:00-08:45'),
        const OcrCell(row: 2, col: 0, text: '08:55-09:40'),
        const OcrCell(row: 1, col: 1, text: '高等数学'),
        const OcrCell(row: 2, col: 1, text: '线性代数'),
      ]);
      final result = ScheduleGridParser.parse(OcrGrid.fromTable(table));
      expect(result.courses[0].startSection, 1);
      expect(result.courses[1].startSection, 2);
      expect(result.header.sectionColumn, -1);
    });

    test('「上午/下午」块标记不误判为节次，退回行序', () {
      final table = OcrTable(cells: [
        ..._dayHeader(),
        const OcrCell(row: 1, col: 0, rowSpan: 4, text: '上午'),
        const OcrCell(row: 5, col: 0, rowSpan: 4, text: '下午'),
        const OcrCell(row: 1, col: 1, text: '早课A'),
        const OcrCell(row: 5, col: 1, text: '午课B'),
      ]);
      final result = ScheduleGridParser.parse(OcrGrid.fromTable(table));
      expect(result.courses[0].startSection, 1);
      expect(result.courses[1].startSection, 5);
    });

    test('找不到星期表头时给出可操作的报错', () {
      final table = OcrTable(cells: [
        const OcrCell(row: 0, col: 0, text: '随便'),
        const OcrCell(row: 1, col: 0, text: '高等数学'),
      ]);
      expect(
        () => ScheduleGridParser.parse(OcrGrid.fromTable(table)),
        throwsA(isA<OcrException>()
            .having((e) => e.code, 'code', 'NO_DAY_HEADER')),
      );
    });
  });

  // ===================== 4. 单元格语义 =====================

  group('CourseCellParser.parse', () {
    test('课程名/教师/地点/周次四行混排', () {
      final out = CourseCellParser.parse('高等数学\n张老师\n教一101\n1-16周');
      expect(out, hasLength(1));
      expect(out.first.name, '高等数学');
      expect(out.first.teacher, '张老师');
      expect(out.first.location, '教一101');
      expect(out.first.weeks, List.generate(16, (i) => i + 1));
    });

    test('括号里的教师 + 单周', () {
      final out = CourseCellParser.parse('大学英语(李老师) 语302 1-16周(单)');
      expect(out, hasLength(1));
      expect(out.first.name, '大学英语');
      expect(out.first.teacher, '李老师');
      expect(out.first.location, '语302');
      expect(out.first.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    });

    test('一格两门课：按周次切换切分', () {
      final out = CourseCellParser.parse('线性代数 1-8周\n大学物理 9-16周');
      expect(out.map((e) => e.name).toList(), ['线性代数', '大学物理']);
      expect(out[0].weeks, List.generate(8, (i) => i + 1));
      expect(out[1].weeks, List.generate(8, (i) => i + 9));
    });

    test('同门课的多个周次区间不被误拆成两门课', () {
      final out = CourseCellParser.parse('高等数学 1-8周\n10-16周');
      expect(out, hasLength(1));
      expect(out.first.name, '高等数学');
      expect(out.first.weeks, [...List.generate(8, (i) => i + 1), ...List.generate(7, (i) => i + 10)]);
    });

    test('无「老师」后缀的纯中文姓名也能识别为教师', () {
      final out = CourseCellParser.parse('概率论与数理统计 李四 A座203');
      expect(out.single.name, '概率论与数理统计');
      expect(out.single.teacher, '李四');
      expect(out.single.location, 'A座203');
    });

    test('课程名里的括号不被误当结构化信息', () {
      final out = CourseCellParser.parse('高等数学(上)\n张三\n教三201');
      expect(out.single.name, '高等数学(上)');
      expect(out.single.teacher, '张三');
      expect(out.single.location, '教三201');
    });

    test('全角字符与全角空格', () {
      final out = CourseCellParser.parse('高等数学（张老师）　教一101　1-16周');
      expect(out.single.name, '高等数学');
      expect(out.single.teacher, '张老师');
      expect(out.single.location, '教一101');
      expect(out.single.weeks, hasLength(16));
    });

    test('文本里的「第1-2节」被丢弃（节次由位置给出）', () {
      final out = CourseCellParser.parse('体育 第3-4节 A操场 1-16周');
      expect(out.single.name, '体育');
      expect(out.single.location, 'A操场');
    });

    test('只有周次、没有课名时不产出课程', () {
      expect(CourseCellParser.parse('1-15单周'), isEmpty);
    });

    test('三格合一的多门课', () {
      final out = CourseCellParser.parse(
          '高等数学 1-4周\n大学物理 5-8周\nC语言 9-16周');
      expect(out.map((e) => e.name).toList(), ['高等数学', '大学物理', 'C语言']);
      expect(out.map((e) => e.weeks!.length).toList(), [4, 4, 8]);
    });
  });

  // ===================== 5. 端到端管线 =====================

  group('OcrImportPipeline.buildDraft', () {
    test('归一化 JSON → 课程草稿', () {
      final result = OcrResult.fromJson(_cloudResponseJson());
      final draft =
          OcrImportPipeline.buildDraft(result, totalWeeks: 16, sourceName: '图片识别');

      expect(draft.courses, hasLength(5));
      expect(draft.sessionCount, 5);
      expect(draft.sourceName, '图片识别');

      Course byName(String n) =>
          draft.courses.firstWhere((c) => c.name == n);

      final math = byName('高等数学');
      expect(math.teacher, '张老师');
      expect(math.sessions.single.dayOfWeek, 1);
      expect(math.sessions.single.startSection, 1);
      expect(math.sessions.single.sectionCount, 2);
      expect(math.sessions.single.location, '教一101');
      expect(math.sessions.single.weeks, List.generate(16, (i) => i + 1));

      final english = byName('大学英语');
      expect(english.sessions.single.dayOfWeek, 2);
      expect(english.sessions.single.startSection, 3);
      expect(english.sessions.single.sectionCount, 2);
      expect(english.sessions.single.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);

      // 一格两门课，落在同一天同一节
      expect(byName('线性代数').sessions.single.dayOfWeek, 3);
      expect(byName('线性代数').sessions.single.weeks, List.generate(8, (i) => i + 1));
      expect(byName('大学物理').sessions.single.dayOfWeek, 3);
      expect(byName('大学物理').sessions.single.weeks, List.generate(8, (i) => i + 9));

      expect(byName('体育').sessions.single.dayOfWeek, 1);
      expect(byName('体育').sessions.single.startSection, 5);
    });

    test('导入的课程按色板轮转上色', () {
      final draft = OcrImportPipeline.buildDraft(
          OcrResult.fromJson(_cloudResponseJson()),
          totalWeeks: 16);
      for (var i = 0; i < draft.courses.length; i++) {
        expect(draft.courses[i].color,
            Course.presetColors[i % Course.presetColors.length]);
      }
    });

    test('倾斜图片会被提示', () {
      final json = _cloudResponseJson();
      json['angle'] = 6.2;
      final draft = OcrImportPipeline.buildDraft(OcrResult.fromJson(json));
      expect(draft.issues.any((i) => i.contains('倾斜')), isTrue);
    });

    test('没有表格时抛可读错误', () {
      expect(
        () => OcrImportPipeline.buildDraft(
            OcrResult.fromJson({'ok': true, 'tables': []})),
        throwsA(isA<OcrException>()
            .having((e) => e.code, 'code', 'NO_TABLE')),
      );
    });

    test('课程格全是纯周次文本时抛 NO_COURSE_NAME', () {
      final table = OcrTable(cells: [
        ..._dayHeader(),
        const OcrCell(row: 1, col: 0, text: '第1节'),
        const OcrCell(row: 1, col: 1, text: '1-16周'),
      ]);
      expect(
        () => OcrImportPipeline.buildDraft(
            OcrResult(tables: [table])),
        throwsA(isA<OcrException>()
            .having((e) => e.code, 'code', 'NO_COURSE_NAME')),
      );
    });
  });

  // ===================== 6. 图片压缩 =====================

  group('HttpOcrClient.prepareImage', () {
    test('长边超限时等比缩小为 JPEG', () {
      final src = img.Image(width: 3200, height: 1600);
      img.fill(src, color: img.ColorRgb8(240, 240, 240));
      final png = Uint8List.fromList(img.encodePng(src));

      final out = HttpOcrClient.prepareImage(png);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, lessThanOrEqualTo(HttpOcrClient.maxImageSide));
      expect(out.length, lessThan(3 * 1024 * 1024));
      // 识别用的是 JPEG
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
    });

    test('小于上限的图片不放大', () {
      final src = img.Image(width: 800, height: 600);
      final png = Uint8List.fromList(img.encodePng(src));
      final out = HttpOcrClient.prepareImage(png);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });

    test('非图片字节给出明确报错', () {
      expect(
        () => HttpOcrClient.prepareImage(Uint8List.fromList(utf8.encode('not an image'))),
        throwsA(isA<OcrException>()
            .having((e) => e.code, 'code', 'BAD_IMAGE')),
      );
    });
  });
}

// ===================== fixtures =====================

/// 标准 7 天表头（第 0 行）
List<OcrCell> _dayHeader() => [
      const OcrCell(row: 0, col: 0, text: '节次'),
      const OcrCell(row: 0, col: 1, text: '星期一'),
      const OcrCell(row: 0, col: 2, text: '星期二'),
      const OcrCell(row: 0, col: 3, text: '星期三'),
      const OcrCell(row: 0, col: 4, text: '星期四'),
      const OcrCell(row: 0, col: 5, text: '星期五'),
      const OcrCell(row: 0, col: 6, text: '星期六'),
      const OcrCell(row: 0, col: 7, text: '星期日'),
    ];

/// 一张有代表性的课表：6 节、含连堂、含一格两门课
OcrTable _scheduleTable() => OcrTable(cells: [
      ..._dayHeader(),
      // 节次列（带时间，验证时间剥离）
      const OcrCell(row: 1, col: 0, text: '第1节\n08:00-08:45'),
      const OcrCell(row: 2, col: 0, text: '第2节\n08:55-09:40'),
      const OcrCell(row: 3, col: 0, text: '第3节\n10:10-10:55'),
      const OcrCell(row: 4, col: 0, text: '第4节\n11:05-11:50'),
      const OcrCell(row: 5, col: 0, text: '第5节\n14:30-15:15'),
      const OcrCell(row: 6, col: 0, text: '第6节\n15:25-16:10'),
      // 课程格
      const OcrCell(
          row: 1, col: 1, rowSpan: 2, text: '高等数学\n张老师\n教一101\n1-16周'),
      const OcrCell(
          row: 3, col: 2, rowSpan: 2, text: '大学英语(李老师) 语302 1-16周(单)'),
      const OcrCell(row: 1, col: 3, text: '线性代数 1-8周\n大学物理 9-16周'),
      const OcrCell(row: 5, col: 1, text: '体育\nA操场\n1-16周'),
    ]);

/// 云函数归一化响应（与 cloud/ocr-proxy 的输出契约一致）
Map<String, dynamic> _cloudResponseJson() => {
      'ok': true,
      'angle': 0.0,
      'requestId': 'test-req',
      'tables': [
        {
          'index': 0,
          'type': 1,
          'rows': 7,
          'cols': 8,
          'cells': _scheduleTable()
              .cells
              .map((c) => {
                    'r': c.row,
                    'c': c.col,
                    'rs': c.rowSpan,
                    'cs': c.colSpan,
                    'text': c.text,
                  })
              .toList(),
        }
      ],
    };
