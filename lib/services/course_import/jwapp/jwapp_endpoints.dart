/// jwapp 学校接入点（一条「适配」= 入口地址 + 模块路径）
///
/// **字段映射不需要逐校写**：jwapp 是金智教育标准产品，接口字段名
/// （`KCM`/`SKXQ`/`KSJC`/`SKZC`…）与响应信封跨校一致，
/// 差异只在部署路径上。所以「适配一所学校」的成本是填两个值，
/// 而不是写一份解析器。
///
/// 已实测：西北农林科技大学（2026-09-29）。
library;

class JwappEndpoints {
  /// 展示名，如「西北农林科技大学」
  final String name;

  /// 登录入口（学校 ehall 首页）。用户在这里完成 CAS 登录。
  final String homeUrl;

  /// jwapp 模块前缀。实测西农为 `/jwapp/sys/wdkbby`。
  final String modulePath;

  /// 课表表名；null 时由响应自动发现（推荐）
  final String? courseTableKey;

  /// 学期配置表名；null 时由响应自动发现（推荐）
  final String? semesterTableKey;

  const JwappEndpoints({
    required this.name,
    required this.homeUrl,
    this.modulePath = defaultModulePath,
    this.courseTableKey,
    this.semesterTableKey,
  });

  static const defaultModulePath = '/jwapp/sys/wdkbby';

  /// 预置：西北农林科技大学（2026-09-29 实测可用）
  static const nwafu = JwappEndpoints(
    name: '西北农林科技大学',
    homeUrl: 'https://ehall.nwafu.edu.cn/',
  );

  static const presets = <JwappEndpoints>[nwafu];

  /// 课表接口路径（学生周课表）
  String get courseTablePath => '$modulePath/modules/xskcb/cxxszhxqkb.do';

  /// 学期配置接口路径（一次返回全部学期的开学日与总周数）
  String get semesterPath => '$modulePath/modules/jshkcb/cxjcs.do';

  bool get isValid =>
      name.trim().isNotEmpty &&
      homeUrl.trim().isNotEmpty &&
      modulePath.trim().isNotEmpty;

  /// 门户主机名
  String get host => Uri.tryParse(homeUrl)?.host ?? '';

  /// 门户源（`https://ehall.nwafu.edu.cn`）。
  /// 注入脚本用它的**绝对地址**取数，这样用户在哪个子页面点了按钮都能命中。
  String get origin => Uri.tryParse(homeUrl)?.origin ?? '';

  /// 由用户输入的域名构造（自定义学校）。只填域名，模块路径沿用默认。
  static JwappEndpoints? fromHostInput(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final home = text.endsWith('/') ? text : '$text/';
    return JwappEndpoints(name: uri.host, homeUrl: home);
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'homeUrl': homeUrl,
        'modulePath': modulePath,
        'courseTableKey': courseTableKey,
        'semesterTableKey': semesterTableKey,
      };

  factory JwappEndpoints.fromMap(Map<String, dynamic> map) => JwappEndpoints(
        name: (map['name'] as String?) ?? '',
        homeUrl: (map['homeUrl'] as String?) ?? '',
        modulePath: (map['modulePath'] as String?)?.trim().isNotEmpty == true
            ? (map['modulePath'] as String)
            : defaultModulePath,
        courseTableKey: map['courseTableKey'] as String?,
        semesterTableKey: map['semesterTableKey'] as String?,
      );
}
