import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diary.dart';
import 'sound_service.dart';

/// 徽章类型
enum BadgeType {
  milestone, // 里程碑徽章（累计不同天数）
  streak, // 连续记录徽章
  totalCount, // 日记总数徽章
  content, // 内容创作徽章
  emotion, // 情感表达徽章
  special, // 特殊成就徽章
  hidden, // 隐藏徽章
  time, // 时间相关徽章
  photo, // 照片相关徽章
}

/// 徽章稀有度
enum BadgeRarity {
  common, // 普通 - 白色
  uncommon, // 罕见 - 绿色
  rare, // 稀有 - 蓝色
  epic, // 史诗 - 紫色
  legendary, // 传说 - 金色
}

/// 徽章配置
class Badge {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final String hiddenDescription;
  final BadgeType type;
  final BadgeRarity rarity;
  final int? requiredDays;
  final int? requiredCount;
  final int? requiredLength;
  final int? requiredPhotos;
  final String? tip;

  const Badge({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.hiddenDescription,
    required this.type,
    required this.rarity,
    this.requiredDays,
    this.requiredCount,
    this.requiredLength,
    this.requiredPhotos,
    this.tip,
  });

  Color get color {
    switch (rarity) {
      case BadgeRarity.common:
        return const Color(0xFFB0BEC5);
      case BadgeRarity.uncommon:
        return const Color(0xFF81C784);
      case BadgeRarity.rare:
        return const Color(0xFF64B5F6);
      case BadgeRarity.epic:
        return const Color(0xFF9575CD);
      case BadgeRarity.legendary:
        return const Color(0xFFFFD54F);
    }
  }
}

/// 徽章服务 - 管理所有徽章的获取和展示
class BadgeService {
  static const String _badgePrefix = 'badge_unlocked_';
  static const String _badgeShownPrefix = 'badge_shown_';
  static const String _newBadgeKey = 'has_new_badge';
  static const String _badgeLastShownKey = 'badge_last_shown_';
  static const String _makeupDaysKey = 'makeup_days_';

  /// 扩展的情感关键词库 - 增加权重分级
  static const Map<String, List<String>> _emotionKeywords = {
    'emotion_love': [
      // 核心爱情词汇
      '爱', '喜欢', '恋爱', '爱情', '感情',
      // 伴侣称呼
      '男朋友', '女朋友', '男友', '女友', '老公', '老婆', '丈夫', '妻子',
      '情人', '对象', '另一半', '那个他', '那个她', 'TA', 'ta',
      '心上人', '意中人', '梦中情人', '白马王子', '白雪公主',
      // 情感表达
      '心动', '心动了', '怦然心动', '心跳', '脸红', '害羞',
      '表白', '告白', '示爱', '追求', '追', '暗恋', '单恋',
      '约会', '见面', '约会了', '一起出去玩', '二人世界',
      '甜蜜', '甜', '好甜', '齁甜', '蜜里调油',
      '想念', '思念', '想你了', '好想你', '惦记', '牵挂',
      '拥抱', '抱抱', '抱', '怀里', '牵手', '拉手', '手牵手',
      '吻', '亲', '亲亲', '接吻', '初吻',
      // 婚姻相关
      '结婚', '婚礼', '婚纱', '钻戒', '求婚', '订婚',
      ' anniversary', '周年纪念', '纪念日', '一周年', '周年',
      '情人节', '七夕', '520', '521', '1314', '一生一世',
      // 关系状态
      '恋人', '爱人', '伴侣', '情侣', '两口子', '小两口',
      '相识', '相恋', '相爱', '在一起', '交往', '确定关系',
      '异地恋', '异国恋', '网恋', '初恋', '前任', '复合',
      // 浪漫元素
      '浪漫', '罗曼蒂克', '情调', '氛围感',
      '惊喜', '感动', '暖心', '贴心', '温柔', '宠溺', '宠爱',
      '礼物', '花', '玫瑰', '巧克力', '戒指', '项链',
      // 情感状态
      '幸福', '恩爱', '相守', '陪伴', '相依', '依偎', '相守一生',
      '白头', '白头偕老', '天长地久', '海枯石烂', '山盟海誓',
      // 网络流行语
      '脱单', '撒狗粮', '秀恩爱', '虐狗', '柠檬', '我酸了',
      '磕到了', '磕糖', '锁了', 'CP', 'cp', '嗑cp',
    ],
    'emotion_family': [
      // 父母称呼
      '爸爸', '爸', '老爸', '爹', '爹地', '爸比',
      '妈妈', '妈', '老妈', '娘', '妈咪', '妈眯',
      '父亲', '母亲', '爸妈', '父母', '双亲', '家长',
      // 祖辈称呼
      '爷爷', '奶奶', '祖父', '祖母', '外公', '外婆',
      '姥爷', '姥姥', '外祖父', '外祖母', '公公', '婆婆',
      '阿公', '阿婆', '老爷子', '老太太',
      // 兄弟姐妹
      '哥哥', '哥', '兄长', '老兄',
      '弟弟', '弟', '老弟', '小弟',
      '姐姐', '姐', '老姐', '大姐',
      '妹妹', '妹', '老妹', '小妹',
      '兄弟', '兄妹', '姐弟', '姐妹', '兄弟姐妹',
      // 其他亲属
      '叔叔', '阿姨', '伯伯', '舅舅', '姑姑', '姨妈', '姑妈',
      '侄子', '侄女', '外甥', '外甥女',
      '堂哥', '堂弟', '堂姐', '堂妹', '表哥', '表弟', '表姐', '表妹',
      '亲人', '亲戚', '亲属', '家人', '家族', '家族群',
      // 家庭概念
      '家庭', '家', '家里', '家中', '回家', '到家', '在家',
      '团聚', '团圆', '团圆饭', '年夜饭', '一家人', '全家',
      '亲情', '亲子', '血缘', '一脉相承', '家风', '家教',
      '老家', '故乡', '家乡', '老家伙', '根', '落叶归根',
      // 家庭行为
      '孝顺', '孝敬', '赡养', '照顾', '照料', '陪伴', '守候',
      '牵挂', '惦记', '操心', '担心', '挂念', '思念家人',
      '打电话回家', '视频通话', '报平安', '嘘寒问暖',
      // 家庭生活
      '吃饭', '做饭', '做菜', '家务', '打扫', '收拾',
      '看电视', '聊天', '唠嗑', '家常', '拉家常',
    ],
    'emotion_work': [
      // 工作基本词汇
      '工作', '上班', '下班', '职场', '职业', '事业', '岗位', '职位',
      // 工作时间
      '加班', '熬夜加班', '通宵', '夜班', '早班', '白班', '倒班',
      '打卡', '签到', '考勤', '迟到', '早退', '旷工',
      '996', '007', '朝九晚五', '八小时', '双休', '单休', '大小周',
      // 工作行为
      '干活', '做事', '忙', '忙碌', '忙活', '赶工', '赶进度', '赶项目',
      '处理', '完成', '搞定', '解决', '推进', '跟进', '落实', '执行',
      '准备', '整理', '汇总', '统计', '分析', '研究', '调研', '调查',
      '写', '写报告', '写方案', '写总结', '写PPT', '做PPT', '做表', '做图',
      '开会', '会议', '讨论', '沟通', '协调', '对接', '联系', '联系客户',
      '汇报', '报告', '述职', '演讲', '发言', '提问', '回答',
      // 工作对象
      '老板', '领导', '上司', '主管', '经理', '总监', '总裁', '董事长',
      '同事', '同僚', '搭档', '伙伴', ' teammate', '团队成员', '组员',
      '下属', '员工', '实习生', '新人', '老员工',
      '客户', '用户', '顾客', '甲方', '乙方', '合作方', '供应商', '渠道',
      // 工作内容
      '项目', '任务', '业务', '活儿', 'case', 'Case', 'CASE',
      '方案', '策划', '计划', '规划', '安排', '部署', '布局',
      '报表', '报告', '文档', '文件', '资料', '数据', '信息', '材料',
      '合同', '协议', '订单', '发票', '收据', '凭证', '审批', '签字',
      '业绩', '绩效', '成果', '成绩', '效果', '效益', '收益', '利润',
      '目标', '指标', 'KPI', 'OKR', 'quota', '任务量', '工作量',
      '考核', '考评', '评估', '评价', '绩效考核', '年终考核',
      // 工作变动
      '入职', '报到', '上岗', '试用', '转正', '升职', '晋升', '提拔',
      '加薪', '涨工资', '调薪', '调岗', '轮岗', '借调', '外派',
      '离职', '辞职', '跳槽', '换工作', '裸辞', '被裁', '裁员', '辞退',
      '面试', '笔试', '一面', '二面', '终面', 'HR面', '技术面',
      '投简历', '求职', '应聘', '招聘', '招人', '挖人', '猎头',
      // 工作福利
      '工资', '薪水', '薪资', '薪酬', '待遇', '收入', '月薪', '年薪',
      '奖金', '年终奖', '分红', '股权', '期权', '股票',
      '补贴', '补助', '津贴', '交通补贴', '餐补', '房补', '通讯补贴',
      '提成', '佣金', '回扣', '小费',
      '假期', '休假', '请假', '事假', '病假', '年假', '带薪假', '调休',
      '出差', '外勤', '报销', '差旅费', '招待费', '办公用品',
      // 工作场所
      '公司', '单位', '企业', '集团', '总部', '分部', '分公司', '子公司',
      '办公室', '工位', '座位', ' desk', '办公桌', '会议室', '会议室',
      '茶水间', '休息室', '食堂', '餐厅', '前台', ' reception',
      '工厂', '车间', '仓库', '门店', '店铺', '柜台',
      // 工作状态
      '努力', '奋斗', '拼搏', '拼命', '认真', '负责', '敬业', '专注',
      '专业', '精通', '熟练', '擅长', '拿手', '专长', '特长',
      '压力大', '累', '疲惫', '累瘫', '累趴', '累坏了', '身心俱疲',
      '忙成狗', '忙死了', '忙疯了', '忙不过来', '焦头烂额', '应接不暇',
      '摸鱼', '划水', '偷懒', '怠工', '磨洋工', '混日子', '打酱油',
      '打工', '打工人', '搬砖', '码农', '程序猿', '产品狗', '运营喵',
      '社畜', '工具人', '螺丝钉', '苦力', '劳动力',
      // 工作感受
      '成就感', '满足感', '充实', '有收获', '有成长', '进步', '提升',
      '挫败', '失败', '搞砸了', '出错了', '失误', '疏忽', '大意',
      '焦虑', '担忧', '发愁', '苦恼', '困扰', '烦', '烦躁', '郁闷',
      '开心', '高兴', '兴奋', '激动', '惊喜', '满意', '认可', '肯定',
      '委屈', '不爽', '不满', '抱怨', '吐槽', '埋怨', '生气', '愤怒',
    ],
    'emotion_dream': [
      // 梦想核心词汇
      '梦想', '梦', '做梦', '追梦', '圆梦', '梦想成真', '美梦', '好梦',
      '目标', '目的', '志向', '抱负', '雄心', '野心', '蓝图', '愿景',
      '理想', '完美的', '向往', '憧憬', '渴望', '期盼', '期待', '愿望',
      // 追求与努力
      '追求', '追寻', '寻找', '探索', '冒险', '尝试', '挑战', '突破',
      '努力', '奋斗', '拼搏', '拼命', '竭尽全力', '全力以赴', '不遗余力',
      '坚持', '毅力', '恒心', '持之以恒', '锲而不舍', '坚持不懈', '永不放弃',
      '自律', '自制', '克制', '忍耐', '忍受', '承受', '承担', '担当',
      // 信心与勇气
      '信心', '自信', '相信自己', '我可以', '我能行', '没问题', '一定行',
      '勇气', '勇敢', '大胆', '无畏', '无惧', '不怕', '敢', '敢于',
      '决心', '决定', '决断', '果断', '毅然', '毅然决然', '破釜沉舟',
      // 希望与未来
      '希望', '期望', '盼望', '期待', '憧憬', '向往', '光明', '曙光',
      '未来', '将来', '前景', '前途', '出路', '方向', '道路', '征程',
      '规划', '计划', '打算', '安排', '筹备', '准备', '布局', '谋划',
      '人生', '人生目标', '人生规划', '人生道路', '人生态度', '人生观',
      '命运', '机遇', '机会', '时机', '缘分', '运气', '造化', '天命',
      // 成长与改变
      '成长', '长大', '成熟', '进步', '提升', '提高', '改善', '改进',
      '改变', '转变', '转型', '蜕变', '进化', '升级', '飞跃', '跨越',
      '学习', '充电', '进修', '深造', '钻研', '研究', '探索', '求知',
      '突破', '打破', '冲破', '超越', '超过', '领先', '领跑', '一流',
      // 成功与失败
      '成功', '胜利', '获胜', '夺冠', '第一名', '冠军', '金牌', '奖杯',
      '成就', '成果', '果实', '收获', '回报', '反馈', '结果', '结局',
      '失败', '失利', '落败', '挫折', '受挫', '碰壁', '栽跟头', '翻车',
      '放弃', '放手', '作罢', '死心', '绝望', '无望', '没戏', '凉了',
      // 迷茫与困惑
      '迷茫', '困惑', '疑惑', '疑问', '不解', '不清楚', '不知道', '无所适从',
      '彷徨', '徘徊', '犹豫', '迟疑', '踌躇', '举棋不定', '左右为难', '纠结',
      '压力', '压抑', '沉重', '负担', '包袱', '累赘', '困扰', '烦恼',
      '焦虑', '着急', '心急', '烦躁', '不安', '忐忑', '七上八下', '坐立不安',
      // 前行与坚持
      '前行', '前进', '向前', '走下去', '继续', '持续', '保持', '维持',
      '出发', '启程', '起航', '上路', '动身', '起步', '开始', '从头开始',
      '在路上', '进行中', '尚未完成', '还在努力', '继续努力', '再接再厉', '加油', '冲',
    ],
    'emotion_travel': [
      // 旅行基本词汇
      '旅行', '旅游', '游', '游玩', '出行', '外出', '出门', '出远门',
      '度假', '休假', '放假', '假期', '假日', '节日', '过节',
      '旅程', '旅途', '行程', '路线', '线路', '目的地', '终点', '起点',
      // 交通工具
      '飞机', '航班', '机票', '登机', '起飞', '降落', '机场', '航站楼',
      '火车', '高铁', '动车', '地铁', '城铁', '轻轨', '列车', '车厢', '卧铺', '硬座',
      '汽车', '大巴', '客车', '公交', '出租车', '网约车', '滴滴', '自驾', '开车', '驾车',
      '轮船', '游轮', '邮轮', '船', '渡轮', '快艇', '帆船',
      '骑行', '骑车', '自行车', '电动车', '摩托车', '徒步', '步行', '走路', '暴走',
      // 住宿
      '酒店', '宾馆', '旅馆', '旅店', '客栈', '民宿', '青旅', '青年旅舍',
      '房间', '客房', '套房', '标间', '大床房', '双人房', '单人间',
      '入住', '退房', '订房', '预订', '预约', '前台', '接待',
      // 景点与景区
      '景点', '景区', '风景区', '旅游区', '度假区', '公园', '乐园', '主题公园',
      '门票', '票', '通票', '套票', '年票', '季票', '免票', '半价', '优惠',
      '导游', '讲解', '解说', '导览', '地图', '攻略', '游记', '路书',
      '打卡', '网红', '网红地', '网红店', '必去', '必游', '推荐', '热门',
      // 拍照与记录
      '拍照', '摄影', '摄像', '录像', '拍视频', 'vlog', 'Vlog', 'VLOG',
      '照片', '相片', '合影', '自拍', '摆拍', '抓拍', '风景照', '人像',
      '相机', '手机', '无人机', '航拍', 'gopro', 'GoPro', '云台', '稳定器',
      // 自然景观
      '风景', '景色', '风光', '美景', '美景', '山水画', '画卷', '如诗如画',
      '山', '山脉', '山峰', '山顶', '山脚', '山坡', '山谷', '山涧', '峡谷',
      '水', '河流', '江水', '湖水', '溪水', '泉水', '瀑布', '湖泊', '潭', '池',
      '海', '海边', '海岸', '海滩', '沙滩', '海水', '海浪', '潮汐', '大海', '海洋',
      '森林', '树林', '林木', '树木', '大树', '古树', '竹林', '竹林',
      '草原', '草地', '草甸', '牧场', '牧区', '牛羊', '骏马',
      '沙漠', '沙丘', '戈壁', '荒漠', '绿洲', '仙人掌',
      '雪山', '冰川', '雪峰', '雪山', '高原', '海拔', '氧气', '高原反应',
      '日出', '日落', '夕阳', '晚霞', '朝霞', '晨曦', '黄昏', '夜幕降临',
      '星空', '银河', '星星', '月亮', '夜空', '天文', '观星', '流星雨',
      // 人文景观
      '古镇', '古城', '古村', '古村落', '老街', '小巷', '胡同', '弄堂',
      '寺庙', '庙宇', '道观', '教堂', '清真寺', '神殿', '佛像', '神像',
      '博物馆', '展览馆', '美术馆', '纪念馆', '故居', '旧址', '遗址',
      '建筑', '古建筑', '现代建筑', '地标', '标志性建筑', '摩天大楼',
      '美食', '小吃', '特色菜', '当地美食', '特产', '土特产', '手信', '纪念品',
      // 出行准备
      '收拾行李', '打包', '整理', '准备', '清单', '必备', '必带',
      '护照', '签证', '身份证', '驾照', '行驶证', '证件', '证明',
      '行李箱', '背包', '双肩包', '旅行包', '手提包', '腰包', '挎包',
      '衣服', '衣物', '换洗', '洗漱', '用品', '装备', '器材',
      '国外', '出境', '入境', '海关', '边检', '安检', '托运', '随身',
      '穷游', '穷游', '自由行', '自助游', '跟团', '跟团游', '旅行团', '团游', '包团',
      '背包客', '驴友', '旅友', '同行', '结伴', '组队', '拼团',
      // 旅行感受
      '放松', '解压', '释放', '逃离', '逃离城市', '远离喧嚣', '清净', '宁静',
      '开心', '快乐', '兴奋', '激动', '期待', '向往', '憧憬', '盼望',
      '累', '疲惫', '累瘫', '走不动', '腿酸', '脚疼', '晒伤', '中暑',
      '震撼', '惊艳', ' breathtaking', '壮观', '壮丽', '宏伟', '美丽', '漂亮',
      '难忘', '印象深刻', '回忆', '记忆', '留念', '纪念', '意义', '有意义',
    ],
    'emotion_happy': [
      // 核心开心词汇
      '开心', '高兴', '快乐', '欢乐', '愉快', '愉悦', '喜悦', '欢喜', '欣喜', '欣悦',
      '爽', '好爽', '太爽了', '爽歪歪', '爽翻天', '痛快', '酣畅', '过瘾',
      '美滋滋', '美', '美好', '美妙', '美丽', '美美哒', '美美的',
      '乐', '乐呵', '乐呵呵', '乐开花', '乐不可支', '乐翻天', '乐滋滋',
      '哈哈', '哈哈哈', '哈哈哈哈', '嘿嘿', '嘻嘻', '呵呵', '吼吼', '233', '666', '牛牛牛',
      // 幸福满足
      '幸福', '幸福感', '好幸福', '真幸福', '太幸福了', '幸福满满',
      '满足', '心满意足', '知足', '知足常乐', '满意', '合意', '称心', '如意', '顺心',
      '甜蜜', '甜', '好甜', '甜甜蜜蜜', '甜到心里', '甜滋滋', '甜丝丝',
      '温馨', '温暖', '暖心', '暖洋洋', '暖融融', '温情', '温柔', '温和',
      // 兴奋激动
      '兴奋', '亢奋', '激动', '激昂', '热血沸腾', '心潮澎湃', '激情', '激情澎湃',
      '惊喜', '又惊又喜', '喜出望外', '喜从天降', '意外之喜', '大大的惊喜',
      '期待', '期盼', '盼望', '憧憬', '向往', '跃跃欲试', '迫不及待',
      // 积极评价
      '棒', '很棒', '太棒了', '棒极了', '棒呆', '厉害', '太厉害了', '厉害了我的',
      '好', '很好', '非常好', '太好了', '真好', '好极了', '好得很', '好棒',
      '优秀', '优异', '出色', '杰出', '卓越', '非凡', '不凡', '了不起',
      '完美', '完美无缺', '十全十美', '尽善尽美', '天衣无缝', '无可挑剔',
      '精彩', '精彩纷呈', '绝妙', '绝佳', '极好', '呱呱叫', '顶呱呱',
      // 成功达成
      '成功', '成了', '搞定', '拿下', '到手', '达成', '实现', '完成', '圆满结束',
      '赢', '赢了', '胜利', '获胜', '得胜', '凯旋', '马到成功', '旗开得胜',
      '突破', '超越', '飞跃', '跨越', '进步', '提升', '成长', '蜕变', '升华',
      '收获', '获得', '得到', '拿到', '收到', '拥有', '具备', '掌握',
      '中奖', '中大奖', '抽中', '摇中', '选中', '幸运儿', '天选之子',
      // 幸运感恩
      '幸运', '运气好', '走运', '好运', '鸿运', '福气', '有福', '有福气', '福分',
      '感恩', '感谢', '谢谢', '感激', '感激不尽', '感恩戴德', '知恩图报',
      '感动', '打动', '触动', '震撼', '感染', '鼓舞', '激励', '振奋', '振作',
      // 身体反应
      '笑', '笑了', '大笑', '欢笑', '眉开眼笑', '喜笑颜开', '笑容满面', '笑逐颜开',
      '开心死了', '开心坏了', '开心到爆', '开心到飞起', '开心得跳起来', '手舞足蹈',
      '心情舒畅', '心情好', '心情愉快', '心情美丽', '心情愉悦', '心境平和',
    ],
    'emotion_sad': [
      // 核心难过词汇
      '难过', '难受', '伤心', '心痛', '心疼', '心酸', '心塞', '心累',
      '悲伤', '悲痛', '哀伤', '忧伤', '忧郁', '愁', '发愁', '忧愁', '哀愁',
      '苦', '痛苦', '苦楚', '苦难', '苦头', '受苦', '遭罪', '受罪',
      '惨', '好惨', '太惨了', '凄惨', '悲惨', '惨烈', '惨痛',
      // 低落情绪
      '沮丧', '懊丧', '颓丧', '丧气', '泄气', '气馁', '灰心', '心灰意冷',
      '失落', '落空', '失望', '绝望', '无望', '没希望', '破灭', '粉碎',
      '郁闷', '烦闷', '烦躁', '焦躁', '焦虑', '着急', '发愁', '苦恼',
      '压抑', '沉闷', '沉闷', '窒息', '喘不过气', '透不过气',
      // 哭泣相关
      '哭', '哭了', '大哭', '痛哭', '哭泣', '啜泣', '抽泣', '呜咽',
      '流泪', '眼泪', '泪水', '泪', '泪珠', '泪花', '泪眼', '泪流满面', '泪如雨下',
      '嚎啕大哭', '放声大哭', '哭鼻子', '抹眼泪', '掉泪', '落泪',
      // 委屈无奈
      '委屈', '憋屈', '冤枉', '冤屈', '受委屈', '被冤枉',
      '无奈', '无可奈何', '没办法', '没辙', '束手无策', '无计可施',
      '无助', '孤立无援', '无依无靠', '无能为力', '力不从心',
      // 孤独寂寞
      '孤独', '孤单', '孤寂', '寂寞', '落寞', '冷清', '凄凉', '苍凉',
      '一个人', '独自一人', '孤身', '只身', '独来独往', '形单影只',
      '空虚', '空洞', '空荡', '空荡荡', '虚无', '飘渺', '茫然', '迷茫',
      // 心碎伤痛
      '心碎', '心碎了', '心都碎了', '心死', '死心', '万念俱灰',
      '痛', '好痛', '太痛了', '痛彻心扉', '痛不欲生', '痛定思痛',
      '伤', '受伤', '伤害', '创伤', '内伤', '外伤', '千疮百孔', '遍体鳞伤',
      // 遗憾后悔
      '遗憾', '惋惜', '可惜', '憾事', '抱憾', '缺憾',
      '后悔', '懊悔', '悔恨', '追悔', '自责', '责备自己', '怪自己',
      '愧疚', '内疚', '惭愧', '羞惭', '对不起', '抱歉', '道歉', '赔礼',
      '如果', '要是', '早知道', '当初', '本来', '原本',
      // 离别失去
      '离别', '分别', '分离', '别离', '分手', '分开', '散伙', '决裂',
      '失去', '丧失', '失落', '丢', '丢了', '丢失', '不见', '没了', '消失',
      '错过', '错失', '擦肩而过', '失之交臂', '悔之晚矣',
      '结束', '完结', '终结', '落幕', '收场', '完蛋', '完蛋了', '凉了', '黄了',
      // 崩溃边缘
      '崩溃', '垮了', '塌了', '完了', '毁了', '完蛋', '死定了', '走投无路',
      '受不了', '受不了', '吃不消', '扛不住', '顶不住', '坚持不住',
      '想死', '不想活', '活着没意思', '生无可恋', '活够了',
    ],
    'emotion_grateful': [
      // 核心感谢词汇
      '感谢', '感激', '感恩', '谢意', '致谢', '鸣谢', '道谢', '称谢',
      '谢谢', '谢谢你', '谢谢您', '多谢', '非常感谢', '万分感谢', '衷心感谢',
      '谢了', '谢啦', '感谢感谢', '谢谢谢谢', '3Q', 'thx', 'thanks',
      // 感恩表达
      '谢天谢地', '感恩戴德', '感激不尽', '感激涕零', '感恩图报', '知恩图报',
      '感恩有你', '感恩遇见', '感恩相识', '感恩陪伴', '感恩支持', '感恩帮助',
      '铭记于心', '没齿难忘', '永世难忘', '终身难忘', '刻骨难忘', '铭记在心',
      // 幸运感慨
      '多亏', '幸亏', '幸好', '好在', '幸而', '幸得', '侥幸', '万幸',
      '幸运', '运气好', '走运', '好运', '鸿运', '福气', '福分', '福报',
      '有幸', '荣幸', '不胜荣幸', '倍感荣幸', '莫大的荣幸', '三生有幸',
      // 珍惜珍重
      '珍惜', '珍爱', '珍视', '珍重', '爱惜', '爱护', '呵护', '守护',
      '宝贵', '珍贵', '可贵', '难得', '来之不易', '千载难逢', '难能可贵',
      '惜福', '知足', '知足常乐', '惜缘', '惜情', '惜时', '珍惜当下',
      // 帮助相关
      '帮助', '帮忙', '协助', '援助', '支援', '救助', '救济', '资助',
      '支持', '支撑', '扶持', '扶助', '力挺', '撑腰', '站台', '背书',
      '关心', '关怀', '关照', '体贴', '照顾', '照料', '照看', '看护',
      '鼓励', '激励', '勉励', '鼓舞', '鞭策', '督促', '督促', '提醒',
      // 师恩友情
      '恩师', '恩师', '导师', '引路人', '伯乐', '贵人', '恩人',
      '友情', '友谊', '情谊', '情义', '深情厚谊', '莫逆之交', '生死之交',
      '知己', '知音', '知心', '贴心', '懂我', '理解', '包容', '体谅',
    ],
  };

  /// 积极情绪词（用于疗愈者徽章）
  static const List<String> _positiveWords = [
    // 核心开心词汇
    '开心', '高兴', '快乐', '欢乐', '愉快', '愉悦', '喜悦', '欢喜', '欣喜',
    '爽', '痛快', '酣畅', '过瘾', '美滋滋', '美', '美好', '美妙',
    '乐', '乐呵', '乐呵呵', '乐开花', '乐不可支', '乐翻天',
    '哈哈', '嘿嘿', '嘻嘻', '呵呵', '233', '666',
    // 幸福满足
    '幸福', '好幸福', '真幸福', '太幸福了', '幸福满满',
    '满足', '心满意足', '知足', '满意', '称心', '如意', '顺心',
    '甜蜜', '甜', '好甜', '温馨', '温暖', '暖心', '温情', '温柔',
    // 兴奋激动
    '兴奋', '亢奋', '激动', '激昂', '热血沸腾', '心潮澎湃', '激情',
    '惊喜', '喜出望外', '喜从天降', '意外之喜',
    '期待', '期盼', '盼望', '憧憬', '向往',
    // 积极评价
    '棒', '很棒', '太棒了', '棒极了', '棒呆', '厉害', '太厉害了',
    '好', '很好', '非常好', '太好了', '真好', '好极了', '好得很', '好棒',
    '优秀', '优异', '出色', '杰出', '卓越', '非凡', '不凡', '了不起',
    '完美', '完美无缺', '十全十美', '尽善尽美', '无可挑剔',
    '精彩', '精彩纷呈', '绝妙', '绝佳', '极好', '呱呱叫', '顶呱呱',
    // 成功达成
    '成功', '成了', '搞定', '拿下', '到手', '达成', '实现', '完成',
    '赢', '赢了', '胜利', '获胜', '得胜', '凯旋', '马到成功', '旗开得胜',
    '突破', '超越', '飞跃', '进步', '提升', '成长', '蜕变', '升华',
    '收获', '获得', '得到', '拿到', '收到', '拥有', '具备', '掌握',
    '中奖', '中大奖', '抽中', '幸运儿', '天选之子',
    // 幸运感恩
    '幸运', '运气好', '走运', '好运', '鸿运', '福气', '有福', '福分',
    '感恩', '感谢', '谢谢', '感激', '感激不尽', '感恩戴德', '知恩图报',
    '感动', '打动', '触动', '震撼', '感染', '鼓舞', '激励', '振奋', '振作',
    // 希望信心
    '希望', '期望', '盼望', '期待', '光明', '曙光', '前景', '前途',
    '信心', '自信', '相信自己', '我可以', '我能行', '没问题', '一定行',
    '勇气', '勇敢', '大胆', '无畏', '无惧', '不怕', '敢', '敢于',
    '决心', '决定', '决断', '果断', '毅然', '破釜沉舟',
    // 身体反应
    '笑', '笑了', '大笑', '欢笑', '眉开眼笑', '喜笑颜开', '笑容满面',
    '开心死了', '开心坏了', '开心到爆', '开心到飞起', '手舞足蹈',
    '心情舒畅', '心情好', '心情愉快', '心情美丽', '心情愉悦',
    // 努力坚持
    '加油', '努力', '奋斗', '拼搏', '拼命', '竭尽全力', '全力以赴',
    '坚持', '毅力', '恒心', '持之以恒', '锲而不舍', '坚持不懈', '永不放弃',
    '自律', '自制', '克制', '忍耐', '忍受', '承受', '承担', '担当',
  ];

  /// 所有徽章定义
  static final List<Badge> _allBadges = [
    const Badge(
      id: 'milestone_1',
      name: '初识日记',
      emoji: '🌱',
      description: '写下第一篇日记，开启记录之旅',
      hiddenDescription: '开始写日记，迈出第一步',
      type: BadgeType.milestone,
      rarity: BadgeRarity.common,
      requiredDays: 1,
      tip: 'Tip: 只要写下第一篇日记就能获得',
    ),
    const Badge(
      id: 'milestone_7',
      name: '一周坚持',
      emoji: '🌿',
      description: '累计记录7天，好习惯正在养成',
      hiddenDescription: '写日记7天',
      type: BadgeType.milestone,
      rarity: BadgeRarity.uncommon,
      requiredDays: 7,
      tip: 'Tip: 累计7天有日记记录',
    ),
    const Badge(
      id: 'milestone_30',
      name: '月度达人',
      emoji: '🌸',
      description: '一个月的陪伴，记录了那么多故事',
      hiddenDescription: '写日记30天',
      type: BadgeType.milestone,
      rarity: BadgeRarity.rare,
      requiredDays: 30,
      tip: 'Tip: 累计30天有日记记录',
    ),
    const Badge(
      id: 'milestone_100',
      name: '百日纪念',
      emoji: '💯',
      description: '一百天的时光，一百篇的故事',
      hiddenDescription: '写日记100天',
      type: BadgeType.milestone,
      rarity: BadgeRarity.epic,
      requiredDays: 100,
      tip: 'Tip: 累计100天有日记记录',
    ),
    const Badge(
      id: 'milestone_365',
      name: '周年盛典',
      emoji: '🌟',
      description: '一整年的陪伴，感谢有你',
      hiddenDescription: '写日记一整年',
      type: BadgeType.milestone,
      rarity: BadgeRarity.legendary,
      requiredDays: 365,
      tip: 'Tip: 累计365天有日记记录',
    ),
    const Badge(
      id: 'streak_3',
      name: '三连击',
      emoji: '🔥',
      description: '连续3天写日记',
      hiddenDescription: '连续坚持3天',
      type: BadgeType.streak,
      rarity: BadgeRarity.common,
      requiredDays: 3,
      tip: 'Tip: 连续写3天就有了',
    ),
    const Badge(
      id: 'streak_7',
      name: '周不懈',
      emoji: '📅',
      description: '连续一周每天写日记',
      hiddenDescription: '连续坚持一周',
      type: BadgeType.streak,
      rarity: BadgeRarity.uncommon,
      requiredDays: 7,
      tip: 'Tip: 一周每天都写，不间断',
    ),
    const Badge(
      id: 'streak_14',
      name: '双周战士',
      emoji: '💪',
      description: '连续14天写日记',
      hiddenDescription: '连续两周坚持',
      type: BadgeType.streak,
      rarity: BadgeRarity.rare,
      requiredDays: 14,
      tip: 'Tip: 连续两周不间断',
    ),
    const Badge(
      id: 'streak_30',
      name: '满勤奖',
      emoji: '🏆',
      description: '连续30天不间断写日记',
      hiddenDescription: '连续坚持一个月',
      type: BadgeType.streak,
      rarity: BadgeRarity.epic,
      requiredDays: 30,
      tip: 'Tip: 连续30天，一天都不能少',
    ),
    const Badge(
      id: 'streak_60',
      name: '双月传奇',
      emoji: '🌙',
      description: '连续60天写日记',
      hiddenDescription: '连续两个月坚持',
      type: BadgeType.streak,
      rarity: BadgeRarity.legendary,
      requiredDays: 60,
      tip: 'Tip: 连续60天不间断',
    ),
    const Badge(
      id: 'streak_100',
      name: '百日不辍',
      emoji: '👑',
      description: '连续100天写日记',
      hiddenDescription: '百日连续记录',
      type: BadgeType.streak,
      rarity: BadgeRarity.legendary,
      requiredDays: 100,
      tip: 'Tip: 连续100天不间断',
    ),
    const Badge(
      id: 'streak_second_chance',
      name: '失而复得',
      emoji: '✨',
      description: '使用补签卡恢复连续记录',
      hiddenDescription: '中断后补签',
      type: BadgeType.streak,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 中断后补签可获得',
    ),
    const Badge(
      id: 'total_10',
      name: '初露锋芒',
      emoji: '📝',
      description: '累计写下10篇日记',
      hiddenDescription: '开始多写几篇日记',
      type: BadgeType.totalCount,
      rarity: BadgeRarity.common,
      requiredCount: 10,
      tip: 'Tip: 累计写10篇日记',
    ),
    const Badge(
      id: 'total_50',
      name: '笔耕不辍',
      emoji: '✒️',
      description: '累计写下50篇日记',
      hiddenDescription: '大量记录生活',
      type: BadgeType.totalCount,
      rarity: BadgeRarity.uncommon,
      requiredCount: 50,
      tip: 'Tip: 累计写50篇日记',
    ),
    const Badge(
      id: 'total_100',
      name: '百篇成就',
      emoji: '💯',
      description: '累计写下100篇日记',
      hiddenDescription: '成为日记达人',
      type: BadgeType.totalCount,
      rarity: BadgeRarity.rare,
      requiredCount: 100,
      tip: 'Tip: 累计写100篇日记',
    ),
    const Badge(
      id: 'total_500',
      name: '著作等身',
      emoji: '📚',
      description: '累计写下500篇日记',
      hiddenDescription: '惊人的记录量',
      type: BadgeType.totalCount,
      rarity: BadgeRarity.epic,
      requiredCount: 500,
      tip: 'Tip: 累计写500篇日记',
    ),
    const Badge(
      id: 'total_1000',
      name: '千篇神话',
      emoji: '🏛️',
      description: '累计写下1000篇日记',
      hiddenDescription: '创造日记历史',
      type: BadgeType.totalCount,
      rarity: BadgeRarity.legendary,
      requiredCount: 1000,
      tip: 'Tip: 累计写1000篇日记',
    ),
    const Badge(
      id: 'content_first',
      name: '初出茅庐',
      emoji: '✍️',
      description: '写下第一篇日记',
      hiddenDescription: '开始创作内容',
      type: BadgeType.content,
      rarity: BadgeRarity.common,
      tip: 'Tip: 写下你的第一篇日记',
    ),
    const Badge(
      id: 'content_100',
      name: '百字短文',
      emoji: '📄',
      description: '单篇日记超过100字',
      hiddenDescription: '写点有内容的东西',
      type: BadgeType.content,
      rarity: BadgeRarity.common,
      requiredLength: 100,
      tip: 'Tip: 写一篇100字以上的日记',
    ),
    const Badge(
      id: 'content_500',
      name: '五百言',
      emoji: '📃',
      description: '单篇日记超过500字',
      hiddenDescription: '写得更多一些',
      type: BadgeType.content,
      rarity: BadgeRarity.uncommon,
      requiredLength: 500,
      tip: 'Tip: 写一篇500字以上的日记',
    ),
    const Badge(
      id: 'content_1000',
      name: '千字文',
      emoji: '📝',
      description: '单篇日记超过1000字',
      hiddenDescription: '写一篇长日记',
      type: BadgeType.content,
      rarity: BadgeRarity.uncommon,
      requiredLength: 1000,
      tip: 'Tip: 写一篇1000字以上的日记',
    ),
    const Badge(
      id: 'content_2000',
      name: '两千字巨作',
      emoji: '📖',
      description: '单篇日记超过2000字',
      hiddenDescription: '写下长篇大论',
      type: BadgeType.content,
      rarity: BadgeRarity.rare,
      requiredLength: 2000,
      tip: 'Tip: 写一篇2000字以上的日记',
    ),
    const Badge(
      id: 'content_with_title',
      name: '标题党',
      emoji: '📰',
      description: '给日记添加标题',
      hiddenDescription: '给日记起个名字',
      type: BadgeType.content,
      rarity: BadgeRarity.common,
      tip: 'Tip: 写一篇有标题的日记',
    ),
    const Badge(
      id: 'content_good_title',
      name: '好标题',
      emoji: '🏷️',
      description: '标题超过10个字',
      hiddenDescription: '起个好标题',
      type: BadgeType.content,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 写一个超过10字的标题',
    ),
    const Badge(
      id: 'content_photo',
      name: '摄影师',
      emoji: '📷',
      description: '在日记中添加第一张照片',
      hiddenDescription: '用图片记录生活',
      type: BadgeType.content,
      rarity: BadgeRarity.common,
      tip: 'Tip: 给日记加张照片试试',
    ),
    const Badge(
      id: 'content_multi_photo',
      name: '九宫格',
      emoji: '🖼️',
      description: '单篇日记添加3张以上照片',
      hiddenDescription: '一次发多张照片',
      type: BadgeType.content,
      rarity: BadgeRarity.uncommon,
      requiredPhotos: 3,
      tip: 'Tip: 一篇日记加3张以上照片',
    ),
    const Badge(
      id: 'content_night',
      name: '夜猫子',
      emoji: '🦉',
      description: '在凌晨0-5点写日记',
      hiddenDescription: '深夜还在写日记',
      type: BadgeType.content,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 凌晨0-5点写日记有惊喜',
    ),
    const Badge(
      id: 'content_morning',
      name: '早起鸟',
      emoji: '🐦',
      description: '在早晨5-8点写日记',
      hiddenDescription: '早起记录生活',
      type: BadgeType.content,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 早起5-8点写日记',
    ),
    const Badge(
      id: 'content_consistent_writer',
      name: '持之以恒',
      emoji: '📅',
      description: '连续3天每天写日记超过300字',
      hiddenDescription: '持续输出',
      type: BadgeType.content,
      rarity: BadgeRarity.rare,
      tip: 'Tip: 连续3天每天写300字以上',
    ),
    const Badge(
      id: 'time_lunch',
      name: '午餐时光',
      emoji: '🍱',
      description: '在午餐时间(11:30-13:30)写日记',
      hiddenDescription: '记录午餐时刻',
      type: BadgeType.time,
      rarity: BadgeRarity.common,
      tip: 'Tip: 午餐时间11:30-13:30写日记',
    ),
    const Badge(
      id: 'time_afternoon',
      name: '下午茶',
      emoji: '☕',
      description: '在下午茶时间(14:00-17:00)写日记',
      hiddenDescription: '悠闲午后记录',
      type: BadgeType.time,
      rarity: BadgeRarity.common,
      tip: 'Tip: 下午时段14:00-17:00写日记',
    ),
    const Badge(
      id: 'time_evening',
      name: '黄昏絮语',
      emoji: '🌆',
      description: '在傍晚(17:00-19:00)写日记',
      hiddenDescription: '记录黄昏时刻',
      type: BadgeType.time,
      rarity: BadgeRarity.common,
      tip: 'Tip: 傍晚时分17:00-19:00写日记',
    ),
    const Badge(
      id: 'time_weekend',
      name: '周末闲情',
      emoji: '🎨',
      description: '在周末写日记',
      hiddenDescription: '周末也不忘记录',
      type: BadgeType.time,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 周六或周日写日记',
    ),
    const Badge(
      id: 'time_sunday_night',
      name: '周日焦虑症',
      emoji: '😰',
      description: '在周日晚上(20:00-24:00)写日记',
      hiddenDescription: '周日晚上特别的心情',
      type: BadgeType.time,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 周日晚上20:00-24:00写日记',
    ),
    const Badge(
      id: 'time_friday_night',
      name: '周五狂欢',
      emoji: '🎉',
      description: '在周五晚上写日记',
      hiddenDescription: '记录周五的快乐',
      type: BadgeType.time,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 周五晚上18:00后写日记',
    ),
    const Badge(
      id: 'time_new_year_eve',
      name: '跨年使者',
      emoji: '🎊',
      description: '在12月31日写日记',
      hiddenDescription: '年末记录',
      type: BadgeType.time,
      rarity: BadgeRarity.rare,
      tip: 'Tip: 12月31日写日记',
    ),
    const Badge(
      id: 'photo_10',
      name: '相册收藏家',
      emoji: '📸',
      description: '累计添加10张照片',
      hiddenDescription: '用照片记录生活',
      type: BadgeType.photo,
      rarity: BadgeRarity.common,
      requiredCount: 10,
      tip: 'Tip: 累计添加10张照片',
    ),
    const Badge(
      id: 'photo_50',
      name: '摄影师',
      emoji: '📷',
      description: '累计添加50张照片',
      hiddenDescription: '成为摄影达人',
      type: BadgeType.photo,
      rarity: BadgeRarity.uncommon,
      requiredCount: 50,
      tip: 'Tip: 累计添加50张照片',
    ),
    const Badge(
      id: 'photo_100',
      name: '影像大师',
      emoji: '🎬',
      description: '累计添加100张照片',
      hiddenDescription: '用影像讲述故事',
      type: BadgeType.photo,
      rarity: BadgeRarity.rare,
      requiredCount: 100,
      tip: 'Tip: 累计添加100张照片',
    ),
    const Badge(
      id: 'photo_daily',
      name: '每日一拍',
      emoji: '🤳',
      description: '连续7天每天添加照片',
      hiddenDescription: '每天用照片记录',
      type: BadgeType.photo,
      rarity: BadgeRarity.rare,
      requiredDays: 7,
      tip: 'Tip: 连续7天每天都加照片',
    ),
    const Badge(
      id: 'photo_quality',
      name: '精选集',
      emoji: '🖼️',
      description: '单篇日记添加5张以上照片',
      hiddenDescription: '用多张照片讲故事',
      type: BadgeType.photo,
      rarity: BadgeRarity.epic,
      requiredPhotos: 5,
      tip: 'Tip: 一篇日记加5张以上照片',
    ),
    const Badge(
      id: 'emotion_happy',
      name: '开心果',
      emoji: '😄',
      description: '连续3天记录开心的心情',
      hiddenDescription: '保持快乐的心情',
      type: BadgeType.emotion,
      rarity: BadgeRarity.uncommon,
      requiredDays: 3,
      tip: 'Tip: 连续3天写开心的事',
    ),
    const Badge(
      id: 'emotion_sad',
      name: '疗愈者',
      emoji: '🫂',
      description: '记录并走出低谷期',
      hiddenDescription: '学会面对情绪',
      type: BadgeType.emotion,
      rarity: BadgeRarity.rare,
      tip: 'Tip: 记录难过的日子，然后走出来',
    ),
    const Badge(
      id: 'emotion_grateful',
      name: '感恩者',
      emoji: '🙏',
      description: '在日记中表达感谢',
      hiddenDescription: '学会感恩生活',
      type: BadgeType.emotion,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 在日记里写感谢的话',
    ),
    const Badge(
      id: 'emotion_love',
      name: '恋爱中人',
      emoji: '💕',
      description: '记录关于爱情的内容',
      hiddenDescription: '写下爱意满满的内容',
      type: BadgeType.emotion,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 写日记提到爱情相关内容',
    ),
    const Badge(
      id: 'emotion_family',
      name: '家人最重要',
      emoji: '👨‍👩‍👧‍👦',
      description: '记录关于家人的内容',
      hiddenDescription: '感恩家人',
      type: BadgeType.emotion,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 写日记提到家人',
    ),
    const Badge(
      id: 'emotion_work',
      name: '打工人',
      emoji: '💼',
      description: '记录关于工作的内容',
      hiddenDescription: '工作日常',
      type: BadgeType.emotion,
      rarity: BadgeRarity.common,
      tip: 'Tip: 写日记提到工作',
    ),
    const Badge(
      id: 'emotion_dream',
      name: '追梦人',
      emoji: '💫',
      description: '记录自己的梦想',
      hiddenDescription: '写下梦想',
      type: BadgeType.emotion,
      rarity: BadgeRarity.rare,
      tip: 'Tip: 写日记提到梦想',
    ),
    const Badge(
      id: 'emotion_travel',
      name: '旅行家',
      emoji: '✈️',
      description: '记录一次旅行',
      hiddenDescription: '用日记记录旅行',
      type: BadgeType.emotion,
      rarity: BadgeRarity.rare,
      tip: 'Tip: 旅行时记得写日记',
    ),
    const Badge(
      id: 'emotion_rollercoaster',
      name: '情绪过山车',
      emoji: '🎢',
      description: '一天内记录了开心和难过的情绪',
      hiddenDescription: '丰富的情感表达',
      type: BadgeType.emotion,
      rarity: BadgeRarity.epic,
      tip: 'Tip: 一天内既有开心又有难过',
    ),
    const Badge(
      id: 'special_rainy',
      name: '雨夜思',
      emoji: '🌧️',
      description: '在雨天写日记',
      hiddenDescription: '特定天气记录',
      type: BadgeType.special,
      rarity: BadgeRarity.common,
      tip: 'Tip: 下雨天写日记试试',
    ),
    const Badge(
      id: 'special_birthday',
      name: '生日星',
      emoji: '🎂',
      description: '在生日当天写日记',
      hiddenDescription: '记录特别的日子',
      type: BadgeType.special,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 生日那天记得写日记',
    ),
    const Badge(
      id: 'special_newyear',
      name: '跨年人',
      emoji: '🎆',
      description: '在元旦写日记',
      hiddenDescription: '新年第一天的记录',
      type: BadgeType.special,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 元旦1月1日写日记开启新的一年',
    ),
    const Badge(
      id: 'special_spring',
      name: '春日序曲',
      emoji: '🌸',
      description: '在春天(3-5月)写日记',
      hiddenDescription: '记录春天的美好',
      type: BadgeType.special,
      rarity: BadgeRarity.common,
      tip: 'Tip: 春天3-5月写日记',
    ),
    const Badge(
      id: 'special_summer',
      name: '夏日炎炎',
      emoji: '☀️',
      description: '在夏天(6-8月)写日记',
      hiddenDescription: '记录盛夏时光',
      type: BadgeType.special,
      rarity: BadgeRarity.common,
      tip: 'Tip: 夏天6-8月写日记',
    ),
    const Badge(
      id: 'special_autumn',
      name: '秋日私语',
      emoji: '🍂',
      description: '在秋天(9-11月)写日记',
      hiddenDescription: '记录金秋时节',
      type: BadgeType.special,
      rarity: BadgeRarity.common,
      tip: 'Tip: 秋天9-11月写日记',
    ),
    const Badge(
      id: 'special_winter',
      name: '冬日暖阳',
      emoji: '❄️',
      description: '在冬天(12-2月)写日记',
      hiddenDescription: '记录寒冷中的温暖',
      type: BadgeType.special,
      rarity: BadgeRarity.common,
      tip: 'Tip: 冬天12-2月写日记',
    ),
    const Badge(
      id: 'special_midyear',
      name: '年中记',
      emoji: '📅',
      description: '在年中(6月)写日记',
      hiddenDescription: '半年时光记录',
      type: BadgeType.special,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 6月写日记',
    ),
    const Badge(
      id: 'special_yearend',
      name: '年终总结',
      emoji: '📊',
      description: '在年末(12月)写日记',
      hiddenDescription: '一年结束记录',
      type: BadgeType.special,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 12月写日记',
    ),
    const Badge(
      id: 'special_first_day',
      name: '新开始',
      emoji: '🌅',
      description: '在每月1号写日记',
      hiddenDescription: '每月第一天',
      type: BadgeType.special,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 每月1号写日记',
    ),
    const Badge(
      id: 'hidden_click',
      name: '探索者',
      emoji: '🔍',
      description: '发现了隐藏的秘密',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.epic,
      tip: 'Tip: 连续点击关于页面试试看',
    ),
    const Badge(
      id: 'hidden_midnight',
      name: '守夜人',
      emoji: '🌙',
      description: '在午夜12点整写日记',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.epic,
      tip: 'Tip: 午夜12点写日记有惊喜',
    ),
    const Badge(
      id: 'hidden_3am',
      name: '凌晨三点',
      emoji: '😴',
      description: '在凌晨3点写日记',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.epic,
      tip: 'Tip: 凌晨3点写日记',
    ),
    const Badge(
      id: 'hidden_10000',
      name: '万字王',
      emoji: '👑',
      description: '累计写日记超过10000字',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.legendary,
      tip: 'Tip: 累计写够10000字',
    ),
    const Badge(
      id: 'hidden_master',
      name: '日记大师',
      emoji: '📚',
      description: '收集10个徽章',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.legendary,
      tip: 'Tip: 收集10个徽章解锁',
    ),
    const Badge(
      id: 'hidden_collector',
      name: '徽章猎人',
      emoji: '🏅',
      description: '收集20个徽章',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.legendary,
      tip: 'Tip: 收集20个徽章',
    ),
    const Badge(
      id: 'hidden_perfectionist',
      name: '完美主义者',
      emoji: '💎',
      description: '收集所有非隐藏徽章',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.legendary,
      tip: 'Tip: 收集所有普通徽章',
    ),
    const Badge(
      id: 'hidden_same_time',
      name: '准时达人',
      emoji: '⏰',
      description: '连续7天在同一小时写日记',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.rare,
      tip: 'Tip: 试试每天同一时间写日记',
    ),
    const Badge(
      id: 'hidden_all_moods',
      name: '情绪大师',
      emoji: '🎭',
      description: '使用过所有心情',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.epic,
      tip: 'Tip: 试试各种心情',
    ),
    const Badge(
      id: 'early_bird',
      name: '早起鸟',
      emoji: '🐦',
      description: '在清晨5-8点写日记',
      hiddenDescription: '清晨写日记',
      type: BadgeType.time,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 早起写日记获得',
    ),
    const Badge(
      id: 'night_owl',
      name: '夜猫子',
      emoji: '🦉',
      description: '在深夜0-5点写日记',
      hiddenDescription: '深夜写日记',
      type: BadgeType.time,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 深夜写日记获得',
    ),
    const Badge(
      id: 'daily_photo',
      name: '每日一拍',
      emoji: '📸',
      description: '连续7天添加照片',
      hiddenDescription: '连续发照片',
      type: BadgeType.photo,
      rarity: BadgeRarity.rare,
      requiredDays: 7,
      tip: 'Tip: 连续7天添加照片',
    ),
    const Badge(
      id: 'legendary_collector',
      name: '传说收藏家',
      emoji: '🏆',
      description: '获得传说祝福',
      hiddenDescription: '???',
      type: BadgeType.hidden,
      rarity: BadgeRarity.legendary,
      tip: 'Tip: 从扭蛋中获得传说祝福',
    ),
    // === 商店购买纪念徽章 ===
    const Badge(
      id: 'shop_first_purchase',
      name: '首次购物',
      emoji: '🛒',
      description: '在商店完成第一次购买',
      hiddenDescription: '开启购物之旅',
      type: BadgeType.special,
      rarity: BadgeRarity.common,
      tip: 'Tip: 在扭蛋商店购买任意商品',
    ),
    const Badge(
      id: 'shop_sticker_collector',
      name: '贴纸收藏家',
      emoji: '🎨',
      description: '累计购买5张贴纸',
      hiddenDescription: '收集喜爱的贴纸',
      type: BadgeType.special,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 在商店购买5张贴纸',
    ),
    const Badge(
      id: 'shop_avatar_master',
      name: '头像达人',
      emoji: '👤',
      description: '累计购买3个头像',
      hiddenDescription: '展示独特个性',
      type: BadgeType.special,
      rarity: BadgeRarity.uncommon,
      tip: 'Tip: 在商店购买3个头像',
    ),
    const Badge(
      id: 'shop_big_spender',
      name: '购物狂',
      emoji: '💸',
      description: '累计消费1000碎片',
      hiddenDescription: '慷慨的消费者',
      type: BadgeType.special,
      rarity: BadgeRarity.rare,
      tip: 'Tip: 在商店累计消费1000碎片',
    ),
    const Badge(
      id: 'shop_vip_customer',
      name: 'VIP顾客',
      emoji: '💎',
      description: '累计购买20件商品',
      hiddenDescription: '商店的忠实顾客',
      type: BadgeType.special,
      rarity: BadgeRarity.epic,
      tip: 'Tip: 在商店累计购买20件商品',
    ),
    const Badge(
      id: 'shop_completionist',
      name: '完美收藏家',
      emoji: '🏅',
      description: '购买商店所有商品',
      hiddenDescription: '收集所有商品',
      type: BadgeType.special,
      rarity: BadgeRarity.legendary,
      tip: 'Tip: 购买商店所有可购买商品',
    ),
  ];

  static List<Badge> get allBadges => List.unmodifiable(_allBadges);

  static Badge? getBadgeById(String id) {
    try {
      return _allBadges.firstWhere((b) => b.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> isUnlocked(String badgeId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_badgePrefix$badgeId') ?? false;
  }

  static Future<bool> unlockBadge(String badgeId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_badgePrefix$badgeId';

    if (prefs.getBool(key) ?? false) {
      return false;
    }

    await prefs.setBool(key, true);
    await prefs.setBool(_newBadgeKey, true);
    await prefs.setInt(
        '$_badgeLastShownKey$badgeId', DateTime.now().millisecondsSinceEpoch);

    return true;
  }

  static Future<List<Badge>> getUnlockedBadges() async {
    final prefs = await SharedPreferences.getInstance();
    final unlocked = <Badge>[];

    for (final badge in _allBadges) {
      if (prefs.getBool('$_badgePrefix${badge.id}') ?? false) {
        unlocked.add(badge);
      }
    }

    return unlocked;
  }

  static Future<List<Badge>> getLockedBadges() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = <Badge>[];

    for (final badge in _allBadges) {
      if (!(prefs.getBool('$_badgePrefix${badge.id}') ?? false)) {
        locked.add(badge);
      }
    }

    return locked;
  }

  static Future<bool> hasNewBadge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_newBadgeKey) ?? false;
  }

  static Future<void> markNewBadgeShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_newBadgeKey, false);
  }

  static Future<String> getRandomTip() async {
    final lockedBadges = await getLockedBadges();
    if (lockedBadges.isEmpty) {
      return '恭喜你！已经收集所有徽章了！🎉';
    }

    final tips = lockedBadges
        .where((b) => b.tip != null && b.tip!.isNotEmpty)
        .map((b) => b.tip!)
        .toList();

    if (tips.isEmpty) {
      return '继续写日记，发现更多惊喜！✨';
    }

    final random = Random();
    return tips[random.nextInt(tips.length)];
  }

  /// 获取所有徽章的tips（用于彩蛋）
  static List<String> getAllBadgeTips() {
    final tips = _allBadges
        .where((b) => b.tip != null && b.tip!.isNotEmpty)
        .map((b) => b.tip!)
        .toList();
    return tips;
  }

  /// 获取随机徽章tip（用于彩蛋，不依赖异步）
  static String getRandomBadgeTip() {
    final tips = getAllBadgeTips();
    if (tips.isEmpty) {
      return 'Tip: 继续写日记，发现更多惊喜！✨';
    }
    final random = Random();
    return tips[random.nextInt(tips.length)];
  }

  static Future<List<Badge>> checkMilestoneBadges(int uniqueDays) async {
    final unlocked = <Badge>[];

    for (final badge in _allBadges) {
      if (badge.type == BadgeType.milestone && badge.requiredDays != null) {
        if (uniqueDays >= badge.requiredDays!) {
          final newlyUnlocked = await unlockBadge(badge.id);
          if (newlyUnlocked) {
            unlocked.add(badge);
          }
        }
      }
    }

    return unlocked;
  }

  static int calculateCurrentStreak(List<Diary> diaries) {
    if (diaries.isEmpty) return 0;

    final dates = diaries
        .map((d) {
          try {
            return DateTime.parse(d.date);
          } catch (e) {
            return null;
          }
        })
        .where((d) => d != null)
        .cast<DateTime>()
        .toList();

    if (dates.isEmpty) return 0;

    dates.sort((a, b) => a.compareTo(b));

    final uniqueDates =
        dates.map((d) => DateTime(d.year, d.month, d.day)).toSet().toList();
    uniqueDates.sort((a, b) => b.compareTo(a));

    if (uniqueDates.isEmpty) return 0;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterdayDate = todayDate.subtract(const Duration(days: 1));

    int streak = 0;
    DateTime checkDate;

    if (uniqueDates.any((d) => d.isAtSameMomentAs(todayDate))) {
      checkDate = todayDate;
    } else if (uniqueDates.any((d) => d.isAtSameMomentAs(yesterdayDate))) {
      checkDate = yesterdayDate;
    } else {
      return 0;
    }

    for (final date in uniqueDates) {
      if (date.isAtSameMomentAs(checkDate)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (date.isBefore(checkDate)) {
        break;
      }
    }

    return streak;
  }

  static Future<int> getMakeupDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_makeupDaysKey) ?? 0;
  }

  static Future<void> addMakeupDay() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getMakeupDays();
    await prefs.setInt(_makeupDaysKey, current + 1);
  }

  static Future<List<Badge>> checkStreakBadges(List<Diary> diaries) async {
    final unlocked = <Badge>[];
    final currentStreak = calculateCurrentStreak(diaries);

    for (final badge in _allBadges) {
      if (badge.type == BadgeType.streak && badge.requiredDays != null) {
        if (currentStreak >= badge.requiredDays!) {
          final newlyUnlocked = await unlockBadge(badge.id);
          if (newlyUnlocked) {
            unlocked.add(badge);
          }
        }
      }
    }

    return unlocked;
  }

  static Future<List<Badge>> checkTotalCountBadges(int totalCount) async {
    final unlocked = <Badge>[];

    for (final badge in _allBadges) {
      if (badge.type == BadgeType.totalCount && badge.requiredCount != null) {
        if (totalCount >= badge.requiredCount!) {
          final newlyUnlocked = await unlockBadge(badge.id);
          if (newlyUnlocked) {
            unlocked.add(badge);
          }
        }
      }
    }

    return unlocked;
  }

  static Future<List<Badge>> checkContentBadges(Diary diary,
      {DateTime? writeTime, List<Diary>? allDiaries}) async {
    final unlocked = <Badge>[];
    final content = diary.content ?? '';
    final title = diary.title;
    final wordCount = content.length;
    final imageCount = diary.imageList.length;

    for (final badge in _allBadges) {
      if (badge.type != BadgeType.content) continue;

      bool shouldUnlock = false;

      // 根据徽章ID精确匹配条件，使用switch语句确保互斥
      switch (badge.id) {
        case 'content_first':
          // 第一篇日记徽章 - 只要有日记记录即可
          shouldUnlock = allDiaries != null && allDiaries.isNotEmpty;
          break;
        case 'content_100':
        case 'content_500':
        case 'content_1000':
        case 'content_2000':
          // 字数徽章 - 检查是否达到特定字数要求
          if (badge.requiredLength != null) {
            shouldUnlock = wordCount >= badge.requiredLength!;
          }
          break;
        case 'content_with_title':
          // 标题徽章 - 有标题即可
          shouldUnlock = title != null && title.isNotEmpty;
          break;
        case 'content_good_title':
          // 好标题徽章 - 标题超过10个字
          shouldUnlock = title != null && title.length >= 10;
          break;
        case 'content_photo':
          // 摄影师徽章 - 添加第一张照片
          shouldUnlock = imageCount >= 1;
          break;
        case 'content_multi_photo':
          // 九宫格徽章 - 单篇3张以上照片
          if (badge.requiredPhotos != null) {
            shouldUnlock = imageCount >= badge.requiredPhotos!;
          }
          break;
        case 'content_night':
          // 夜猫子徽章 - 凌晨0-5点写日记
          if (writeTime != null) {
            shouldUnlock = writeTime.hour >= 0 && writeTime.hour < 5;
          }
          break;
        case 'content_morning':
          // 早起鸟徽章 - 早晨5-8点写日记
          if (writeTime != null) {
            shouldUnlock = writeTime.hour >= 5 && writeTime.hour < 8;
          }
          break;
        case 'content_consistent_writer':
          // 持之以恒徽章 - 连续3天每天写300字以上
          if (allDiaries != null) {
            shouldUnlock = await _checkConsistentWriter(allDiaries);
          }
          break;
      }

      if (shouldUnlock) {
        final newlyUnlocked = await unlockBadge(badge.id);
        if (newlyUnlocked) {
          unlocked.add(badge);
        }
      }
    }

    return unlocked;
  }

  static Future<bool> _checkConsistentWriter(List<Diary> diaries) async {
    if (diaries.length < 3) return false;

    // 按日期分组，获取每天的日记
    final Map<String, List<Diary>> diariesByDate = {};
    for (final diary in diaries) {
      final date = diary.date;
      if (!diariesByDate.containsKey(date)) {
        diariesByDate[date] = [];
      }
      diariesByDate[date]!.add(diary);
    }

    // 获取所有有日记的日期并排序（降序）
    final dates = diariesByDate.keys.toList();
    dates.sort((a, b) => b.compareTo(a));

    if (dates.length < 3) return false;

    // 检查最近连续3天是否每天都写了300字以上
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    // 确定起始检查日期（今天或昨天）
    String checkDateStr;
    if (dates.contains(todayStr)) {
      checkDateStr = todayStr;
    } else if (dates.contains(yesterdayStr)) {
      checkDateStr = yesterdayStr;
    } else {
      return false;
    }

    int consecutiveDays = 0;
    for (int i = 0; i < 3; i++) {
      final currentDate =
          DateTime.parse(checkDateStr).subtract(Duration(days: i));
      final currentDateStr =
          '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';

      if (diariesByDate.containsKey(currentDateStr)) {
        // 检查这一天是否有日记字数超过300
        final dayDiaries = diariesByDate[currentDateStr]!;
        final hasLongDiary =
            dayDiaries.any((d) => (d.content ?? '').length >= 300);
        if (hasLongDiary) {
          consecutiveDays++;
        } else {
          break;
        }
      } else {
        break;
      }
    }

    return consecutiveDays >= 3;
  }

  static Future<List<Badge>> checkTimeBadges(DateTime writeTime) async {
    final unlocked = <Badge>[];
    final hour = writeTime.hour;
    final minute = writeTime.minute;
    final weekday = writeTime.weekday;
    final month = writeTime.month;
    final day = writeTime.day;

    for (final badge in _allBadges) {
      if (badge.type != BadgeType.time) continue;

      bool shouldUnlock = false;

      switch (badge.id) {
        case 'time_lunch':
          if ((hour == 11 && minute >= 30) ||
              hour == 12 ||
              (hour == 13 && minute < 30)) {
            shouldUnlock = true;
          }
          break;
        case 'time_afternoon':
          if (hour >= 14 && hour < 17) shouldUnlock = true;
          break;
        case 'time_evening':
          if (hour >= 17 && hour < 19) shouldUnlock = true;
          break;
        case 'time_weekend':
          if (weekday == 6 || weekday == 7) shouldUnlock = true;
          break;
        case 'time_sunday_night':
          if (weekday == 7 && hour >= 20) shouldUnlock = true;
          break;
        case 'time_friday_night':
          if (weekday == 5 && hour >= 18) shouldUnlock = true;
          break;
        case 'time_new_year_eve':
          if (month == 12 && day == 31) shouldUnlock = true;
          break;
      }

      if (shouldUnlock) {
        final newlyUnlocked = await unlockBadge(badge.id);
        if (newlyUnlocked) {
          unlocked.add(badge);
        }
      }
    }

    return unlocked;
  }

  static Future<List<Badge>> checkPhotoBadges(List<Diary> allDiaries) async {
    final unlocked = <Badge>[];

    int totalPhotos = 0;
    for (final diary in allDiaries) {
      totalPhotos += diary.imageList.length;
    }

    int photoStreak = 0;
    final datesWithPhotos = allDiaries
        .where((d) => d.imageList.isNotEmpty)
        .map((d) {
          try {
            return DateTime.parse(d.date);
          } catch (e) {
            return null;
          }
        })
        .where((d) => d != null)
        .cast<DateTime>()
        .toList();

    if (datesWithPhotos.isNotEmpty) {
      final uniqueDatesWithPhotos = datesWithPhotos
          .map((d) => DateTime(d.year, d.month, d.day))
          .toSet()
          .toList();
      uniqueDatesWithPhotos.sort((a, b) => b.compareTo(a));

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      DateTime? checkDate;
      if (uniqueDatesWithPhotos.any((d) => d.isAtSameMomentAs(todayDate))) {
        checkDate = todayDate;
      } else {
        checkDate = todayDate.subtract(const Duration(days: 1));
      }

      for (final date in uniqueDatesWithPhotos) {
        if (date.isAtSameMomentAs(checkDate!)) {
          photoStreak++;
          checkDate = checkDate.subtract(const Duration(days: 1));
        } else if (date.isBefore(checkDate)) {
          break;
        }
      }
    }

    Diary? maxPhotoDiary;
    int maxPhotos = 0;
    for (final diary in allDiaries) {
      if (diary.imageList.length > maxPhotos) {
        maxPhotos = diary.imageList.length;
        maxPhotoDiary = diary;
      }
    }

    for (final badge in _allBadges) {
      if (badge.type != BadgeType.photo) continue;

      bool shouldUnlock = false;

      // 根据徽章ID精确匹配条件
      switch (badge.id) {
        case 'photo_10':
        case 'photo_50':
        case 'photo_100':
          // 累计照片数量徽章
          if (badge.requiredCount != null) {
            shouldUnlock = totalPhotos >= badge.requiredCount!;
          }
          break;
        case 'photo_daily':
          // 每日一拍徽章 - 连续7天添加照片
          if (badge.requiredDays != null) {
            shouldUnlock = photoStreak >= badge.requiredDays!;
          }
          break;
        case 'photo_quality':
          // 精选集徽章 - 单篇5张以上照片
          shouldUnlock = maxPhotoDiary != null && maxPhotos >= 5;
          break;
      }

      if (shouldUnlock) {
        final newlyUnlocked = await unlockBadge(badge.id);
        if (newlyUnlocked) {
          unlocked.add(badge);
        }
      }
    }

    return unlocked;
  }

  /// 否定词列表 - 用于检测关键词是否被否定
  static const List<String> _negativeWords = [
    '不',
    '没',
    '无',
    '非',
    '勿',
    '别',
    '未',
    '莫',
    '没有',
    '不是',
    '不会',
    '不能',
    '不要',
    '不敢',
    '不想',
    '不愿',
    '不太',
    '不怎么',
    '算不上',
    '谈不上',
    '称不上',
    '缺乏',
    '缺少',
    '缺失',
    '失去',
    '丧失',
  ];

  /// 正面情感关键词列表 - 用于检测"否定+正面"的情况
  /// 当这些词被否定时，应该触发难过类徽章
  static const List<String> _positiveEmotionKeywords = [
    // 开心类
    '开心', '高兴', '快乐', '欢乐', '愉快', '愉悦', '喜悦', '欢喜', '欣喜',
    '爽', '痛快', '酣畅', '过瘾', '美滋滋', '美', '美好', '美妙',
    '乐', '乐呵', '乐呵呵', '乐开花', '乐不可支', '乐翻天',
    '哈哈', '嘿嘿', '嘻嘻', '呵呵',
    // 幸福类
    '幸福', '好幸福', '真幸福', '太幸福了', '幸福满满',
    '满足', '心满意足', '知足', '满意', '称心', '如意', '顺心',
    '甜蜜', '甜', '好甜', '温馨', '温暖', '暖心', '温情', '温柔',
    // 兴奋类
    '兴奋', '亢奋', '激动', '激昂', '热血沸腾', '心潮澎湃', '激情',
    '惊喜', '喜出望外', '喜从天降', '意外之喜',
    '期待', '期盼', '盼望', '憧憬', '向往',
    // 积极评价
    '棒', '很棒', '太棒了', '棒极了', '棒呆', '厉害', '太厉害了',
    '好', '很好', '非常好', '太好了', '真好', '好极了', '好得很', '好棒',
    '优秀', '优异', '出色', '杰出', '卓越', '非凡', '不凡', '了不起',
    '完美', '完美无缺', '十全十美', '尽善尽美', '无可挑剔',
    '精彩', '精彩纷呈', '绝妙', '绝佳', '极好', '呱呱叫', '顶呱呱',
    // 成功类
    '成功', '成了', '搞定', '拿下', '到手', '达成', '实现', '完成',
    '赢', '赢了', '胜利', '获胜', '得胜', '凯旋', '马到成功', '旗开得胜',
    '突破', '超越', '飞跃', '进步', '提升', '成长', '蜕变', '升华',
    '收获', '获得', '得到', '拿到', '收到', '拥有', '具备', '掌握',
    '中奖', '中大奖', '抽中', '幸运儿', '天选之子',
    // 幸运感恩
    '幸运', '运气好', '走运', '好运', '鸿运', '福气', '有福', '福分',
    '感恩', '感谢', '谢谢', '感激', '感激不尽', '感恩戴德', '知恩图报',
    '感动', '打动', '触动', '震撼', '感染', '鼓舞', '激励', '振奋', '振作',
    // 希望信心
    '希望', '期望', '盼望', '期待', '光明', '曙光', '前景', '前途',
    '信心', '自信', '相信自己', '我可以', '我能行', '没问题', '一定行',
    '勇气', '勇敢', '大胆', '无畏', '无惧', '不怕', '敢', '敢于',
    '决心', '决定', '决断', '果断', '毅然', '破釜沉舟',
    // 身体反应
    '笑', '笑了', '大笑', '欢笑', '眉开眼笑', '喜笑颜开', '笑容满面',
    '开心死了', '开心坏了', '开心到爆', '开心到飞起', '手舞足蹈',
    '心情舒畅', '心情好', '心情愉快', '心情美丽', '心情愉悦',
    // 努力坚持
    '加油', '努力', '奋斗', '拼搏', '拼命', '竭尽全力', '全力以赴',
    '坚持', '毅力', '恒心', '持之以恒', '锲而不舍', '坚持不懈', '永不放弃',
    '自律', '自制', '克制', '忍耐', '忍受', '承受', '承担', '担当',
  ];

  /// 智能检测文本中是否包含有效关键词（排除被否定词修饰的情况）
  ///
  /// 检测逻辑：
  /// 1. 找到关键词在文本中的位置
  /// 2. 检查关键词前面是否有否定词（在关键词前0-6个字符范围内）
  /// 3. 如果有否定词，则认为该关键词无效
  static bool _hasValidKeyword(String text, List<String> keywords) {
    for (final keyword in keywords) {
      final lowerKeyword = keyword.toLowerCase();
      final lowerText = text.toLowerCase();

      int index = 0;
      while (true) {
        index = lowerText.indexOf(lowerKeyword, index);
        if (index == -1) break;

        // 检查这个关键词是否被否定
        if (!_isNegated(lowerText, index)) {
          return true; // 找到一个有效关键词
        }

        index += lowerKeyword.length; // 继续搜索下一个匹配
      }
    }
    return false;
  }

  /// 检测文本中是否包含"否定词+正面关键词"的组合
  /// 用于触发难过类徽章
  static bool _hasNegatedPositiveKeyword(String text) {
    for (final keyword in _positiveEmotionKeywords) {
      final lowerKeyword = keyword.toLowerCase();
      final lowerText = text.toLowerCase();

      int index = 0;
      while (true) {
        index = lowerText.indexOf(lowerKeyword, index);
        if (index == -1) break;

        // 检查这个正面关键词是否被否定
        if (_isNegated(lowerText, index)) {
          return true; // 找到一个被否定的正面关键词
        }

        index += lowerKeyword.length;
      }
    }
    return false;
  }

  /// 检查指定位置的关键词是否被否定词修饰
  ///
  /// [text]: 小写文本
  /// [keywordIndex]: 关键词在文本中的起始位置
  static bool _isNegated(String text, int keywordIndex) {
    // 检查关键词前最多6个字符（否定词通常很短）
    final startPos = keywordIndex > 6 ? keywordIndex - 6 : 0;
    final beforeText = text.substring(startPos, keywordIndex);

    // 检查是否包含否定词
    for (final negWord in _negativeWords) {
      if (beforeText.contains(negWord.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static Future<List<Badge>> checkEmotionBadges(Diary diary,
      {List<Diary>? allDiaries}) async {
    final unlocked = <Badge>[];
    final content = (diary.content ?? '').toLowerCase();
    final title = (diary.title ?? '').toLowerCase();
    final fullText = '$title $content';

    for (final badge in _allBadges) {
      if (badge.type != BadgeType.emotion) continue;

      bool shouldUnlock = false;

      // 情绪过山车徽章 - 同时包含开心和难过的关键词
      if (badge.id == 'emotion_rollercoaster') {
        final happyKeywords = _emotionKeywords['emotion_happy'];
        final sadKeywords = _emotionKeywords['emotion_sad'];
        final hasHappy =
            happyKeywords != null && _hasValidKeyword(fullText, happyKeywords);
        final hasSad =
            sadKeywords != null && _hasValidKeyword(fullText, sadKeywords);
        shouldUnlock = hasHappy && hasSad;
      }
      // 开心果徽章 - 需要连续3天记录开心
      else if (badge.id == 'emotion_happy') {
        final happyKeywords = _emotionKeywords['emotion_happy'];
        if (happyKeywords != null) {
          final hasHappy = _hasValidKeyword(fullText, happyKeywords);
          if (hasHappy && allDiaries != null) {
            final happyStreak =
                _calculateEmotionStreak(allDiaries, happyKeywords);
            shouldUnlock = happyStreak >= 3;
          }
        }
      }
      // 疗愈者徽章 - 记录难过且最近有快乐记录
      // 检测条件：1. 包含难过关键词 或 2. 包含"否定词+正面关键词"
      else if (badge.id == 'emotion_sad') {
        final sadKeywords = _emotionKeywords['emotion_sad'];
        if (sadKeywords != null) {
          // 检测难过关键词（未被否定的）
          final hasSadKeyword = _hasValidKeyword(fullText, sadKeywords);
          // 检测"否定词+正面关键词"（如"不开心"、"不快乐"）
          final hasNegatedPositive = _hasNegatedPositiveKeyword(fullText);

          final hasSad = hasSadKeyword || hasNegatedPositive;

          if (hasSad && allDiaries != null) {
            final recentlyHadHappy = _checkRecentlyHadHappy(allDiaries, diary);
            shouldUnlock = recentlyHadHappy;
          }
        }
      }
      // 其他情感徽章 - 检测对应关键词
      else {
        final badgeKeywords = _emotionKeywords[badge.id];
        if (badgeKeywords != null) {
          shouldUnlock = _hasValidKeyword(fullText, badgeKeywords);
        }
      }

      if (shouldUnlock) {
        final newlyUnlocked = await unlockBadge(badge.id);
        if (newlyUnlocked) {
          unlocked.add(badge);
        }
      }
    }

    return unlocked;
  }

  static int _calculateEmotionStreak(
      List<Diary> diaries, List<String> keywords) {
    if (diaries.isEmpty) return 0;

    final sortedDiaries = List<Diary>.from(diaries);
    sortedDiaries.sort((a, b) => a.date.compareTo(b.date));

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterdayDate = todayDate.subtract(const Duration(days: 1));

    int streak = 0;
    DateTime checkDate;

    final hasToday = sortedDiaries.any((d) {
      try {
        final date = DateTime.parse(d.date);
        return date.year == todayDate.year &&
            date.month == todayDate.month &&
            date.day == todayDate.day;
      } catch (e) {
        return false;
      }
    });

    final hasYesterday = sortedDiaries.any((d) {
      try {
        final date = DateTime.parse(d.date);
        return date.year == yesterdayDate.year &&
            date.month == yesterdayDate.month &&
            date.day == yesterdayDate.day;
      } catch (e) {
        return false;
      }
    });

    if (!hasToday && !hasYesterday) return 0;

    checkDate = hasToday ? todayDate : yesterdayDate;

    final reversedDiaries = sortedDiaries.reversed.toList();
    for (final diary in reversedDiaries) {
      try {
        final date = DateTime.parse(diary.date);
        final dateOnly = DateTime(date.year, date.month, date.day);

        if (dateOnly.isAtSameMomentAs(checkDate)) {
          final text =
              '${diary.title ?? ''} ${diary.content ?? ''}'.toLowerCase();
          final hasKeyword = _hasValidKeyword(text, keywords);
          if (hasKeyword) {
            streak++;
            checkDate = checkDate.subtract(const Duration(days: 1));
          } else {
            break;
          }
        } else if (dateOnly.isBefore(checkDate)) {
          break;
        }
      } catch (e) {
        continue;
      }
    }

    return streak;
  }

  static bool _checkRecentlyHadHappy(List<Diary> diaries, Diary currentDiary) {
    final currentIndex = diaries.indexWhere((d) => d.id == currentDiary.id);
    if (currentIndex <= 0) return false;

    for (int i = currentIndex - 1; i >= 0 && i >= currentIndex - 10; i--) {
      final text =
          '${diaries[i].title ?? ''} ${diaries[i].content ?? ''}'.toLowerCase();
      if (_hasValidKeyword(text, _positiveWords)) {
        return true;
      }
    }

    return false;
  }

  static Future<List<Badge>> checkSpecialBadges(Diary diary,
      {DateTime? writeTime}) async {
    final unlocked = <Badge>[];

    final dateToCheck = writeTime ??
        (diary.date.isNotEmpty
            ? DateTime.tryParse(diary.date) ?? DateTime.now()
            : DateTime.now());

    final month = dateToCheck.month;
    final day = dateToCheck.day;

    for (final badge in _allBadges) {
      if (badge.type != BadgeType.special) continue;

      bool shouldUnlock = false;

      switch (badge.id) {
        case 'special_rainy':
          final weather = (diary.weather ?? '').toLowerCase();
          final content = (diary.content ?? '').toLowerCase();
          if (weather.contains('雨') ||
              content.contains('雨') ||
              content.contains('下雨') ||
              content.contains('雨天')) {
            shouldUnlock = true;
          }
          break;
        case 'special_birthday':
          if (day == DateTime.now().day && month == DateTime.now().month) {
            shouldUnlock = true;
          }
          final content = (diary.content ?? '').toLowerCase();
          if (content.contains('生日') ||
              content.contains('出生') ||
              content.contains('寿星') ||
              content.contains('蛋糕')) {
            shouldUnlock = true;
          }
          break;
        case 'special_newyear':
          if (month == 1 && day == 1) {
            shouldUnlock = true;
          }
          break;
        case 'special_travel':
          final content = (diary.content ?? '').toLowerCase();
          final title = (diary.title ?? '').toLowerCase();
          final fullText = '$title $content';
          final travelKeywords = _emotionKeywords['emotion_travel'];
          if (travelKeywords != null &&
              _hasValidKeyword(fullText, travelKeywords)) {
            shouldUnlock = true;
          }
          break;
        case 'special_spring':
          if (month >= 3 && month <= 5) shouldUnlock = true;
          break;
        case 'special_summer':
          if (month >= 6 && month <= 8) shouldUnlock = true;
          break;
        case 'special_autumn':
          if (month >= 9 && month <= 11) shouldUnlock = true;
          break;
        case 'special_winter':
          if (month == 12 || month == 1 || month == 2) shouldUnlock = true;
          break;
        case 'special_midyear':
          if (month == 6) shouldUnlock = true;
          break;
        case 'special_yearend':
          if (month == 12) shouldUnlock = true;
          break;
        case 'special_first_day':
          if (day == 1) shouldUnlock = true;
          break;
      }

      if (shouldUnlock) {
        final newlyUnlocked = await unlockBadge(badge.id);
        if (newlyUnlocked) {
          unlocked.add(badge);
        }
      }
    }

    return unlocked;
  }

  static Future<List<Badge>> checkHiddenBadges(List<Diary> allDiaries,
      {DateTime? writeTime}) async {
    final unlocked = <Badge>[];

    int totalChars = 0;
    for (final diary in allDiaries) {
      totalChars += diary.wordCount;
    }

    final unlockedBadges = await getUnlockedBadges();
    final unlockedCount = unlockedBadges.length;

    final nonHiddenBadges =
        _allBadges.where((b) => b.type != BadgeType.hidden).toList();
    final nonHiddenCount = nonHiddenBadges.length;

    DateTime? timeToCheck;
    if (writeTime != null) {
      timeToCheck = writeTime;
    } else if (allDiaries.isNotEmpty) {
      try {
        timeToCheck = DateTime.parse(allDiaries.last.date);
      } catch (e) {
        timeToCheck = DateTime.now();
      }
    }

    for (final badge in _allBadges) {
      if (badge.type != BadgeType.hidden) continue;

      bool shouldUnlock = false;

      switch (badge.id) {
        case 'hidden_10000':
          if (totalChars >= 10000) shouldUnlock = true;
          break;
        case 'hidden_master':
          if (unlockedCount >= 10) shouldUnlock = true;
          break;
        case 'hidden_collector':
          if (unlockedCount >= 20) shouldUnlock = true;
          break;
        case 'hidden_perfectionist':
          final unlockedNonHidden =
              unlockedBadges.where((b) => b.type != BadgeType.hidden).length;
          if (unlockedNonHidden >= nonHiddenCount) shouldUnlock = true;
          break;
        case 'hidden_midnight':
          // 守夜人徽章 - 在午夜12点整写日记（00:00-00:05之间）
          if (timeToCheck != null &&
              timeToCheck.hour == 0 &&
              timeToCheck.minute >= 0 &&
              timeToCheck.minute <= 5) {
            shouldUnlock = true;
          }
          break;
        case 'hidden_3am':
          if (timeToCheck != null && timeToCheck.hour == 3) {
            shouldUnlock = true;
          }
          break;
        case 'hidden_same_time':
          if (await _checkSameTime(allDiaries)) shouldUnlock = true;
          break;
        case 'hidden_all_moods':
          if (await _checkAllMoods(allDiaries)) shouldUnlock = true;
          break;
      }

      if (shouldUnlock) {
        final newlyUnlocked = await unlockBadge(badge.id);
        if (newlyUnlocked) {
          unlocked.add(badge);
        }
      }
    }

    return unlocked;
  }

  static Future<bool> _checkSameTime(List<Diary> diaries) async {
    if (diaries.length < 7) return false;

    final sortedDiaries = List<Diary>.from(diaries);
    sortedDiaries.sort((a, b) => b.date.compareTo(a.date));

    final last7 = sortedDiaries.take(7).toList();
    int? commonHour;

    for (final d in last7) {
      try {
        final date = DateTime.parse(d.date);
        if (commonHour == null) {
          commonHour = date.hour;
        } else if (date.hour != commonHour) {
          return false;
        }
      } catch (e) {
        return false;
      }
    }

    return true;
  }

  static Future<bool> _checkAllMoods(List<Diary> diaries) async {
    final usedMoods = <String>{};
    for (final d in diaries) {
      if (d.moodName != null && d.moodName!.isNotEmpty) {
        usedMoods.add(d.moodName!);
      }
    }
    return usedMoods.length >= 5;
  }

  static Future<List<Badge>> checkAllBadges(
    Diary diary,
    List<Diary> allDiaries, {
    DateTime? writeTime,
  }) async {
    final unlocked = <Badge>[];

    final uniqueDates = allDiaries.map((d) => d.date).toSet();
    final uniqueDays = uniqueDates.length;
    final totalCount = allDiaries.length;

    unlocked.addAll(await checkMilestoneBadges(uniqueDays));
    unlocked.addAll(await checkStreakBadges(allDiaries));
    unlocked.addAll(await checkTotalCountBadges(totalCount));
    unlocked.addAll(await checkContentBadges(diary,
        writeTime: writeTime, allDiaries: allDiaries));

    if (writeTime != null) {
      unlocked.addAll(await checkTimeBadges(writeTime));
    }

    unlocked.addAll(await checkEmotionBadges(diary, allDiaries: allDiaries));
    unlocked.addAll(await checkPhotoBadges(allDiaries));
    unlocked.addAll(await checkSpecialBadges(diary, writeTime: writeTime));
    unlocked.addAll(await checkHiddenBadges(allDiaries, writeTime: writeTime));

    return unlocked;
  }

  static Future<bool> unlockExplorerBadge() async {
    return await unlockBadge('hidden_click');
  }

  static Future<void> resetAllBadges() async {
    final prefs = await SharedPreferences.getInstance();
    for (final badge in _allBadges) {
      await prefs.remove('$_badgePrefix${badge.id}');
      await prefs.remove('$_badgeShownPrefix${badge.id}');
      await prefs.remove('$_badgeLastShownKey${badge.id}');
    }
    await prefs.remove(_newBadgeKey);
    await prefs.remove(_makeupDaysKey);
  }
}

class BadgeUnlockDialog extends StatefulWidget {
  final Badge badge;

  const BadgeUnlockDialog({
    super.key,
    required this.badge,
  });

  static Future<void> show(BuildContext context, Badge badge) {
    // 播放徽章解锁音效
    SoundService.playBadgeUnlock();

    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7), // 更深的背景遮罩
      useSafeArea: true,
      builder: (context) => WillPopScope(
        // 禁止返回键关闭
        onWillPop: () async => false,
        child: BadgeUnlockDialog(badge: badge),
      ),
    );
  }

  @override
  State<BadgeUnlockDialog> createState() => _BadgeUnlockDialogState();
}

class _BadgeUnlockDialogState extends State<BadgeUnlockDialog>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _shineAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800), // 加快动画速度
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 40,
      ),
    ]).animate(_controller);

    _rotateAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.5, end: 0.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.1, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.0),
        weight: 50,
      ),
    ]).animate(_controller);

    _shineAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: -1.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0)
            .chain(CurveTween(curve: Curves.linear)),
        weight: 50,
      ),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: widget.badge.color.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 徽章图标动画
                Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Transform.rotate(
                    angle: _rotateAnimation.value,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.badge.color.withValues(alpha: 0.9),
                            widget.badge.color.withValues(alpha: 0.5),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: widget.badge.color.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.badge.emoji,
                          style: const TextStyle(fontSize: 56),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 标题
                const Text(
                  '解锁新徽章！',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),
                // 徽章名称
                Text(
                  widget.badge.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: widget.badge.color,
                  ),
                ),
                const SizedBox(height: 8),
                // 描述
                Text(
                  widget.badge.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4A4A6A),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                // 确定按钮
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.badge.color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('太棒了！'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 批量徽章解锁弹窗 - 同时显示多个徽章
class BatchBadgeUnlockDialog extends StatefulWidget {
  final List<Badge> badges;

  const BatchBadgeUnlockDialog({
    super.key,
    required this.badges,
  });

  static Future<void> show(BuildContext context, List<Badge> badges) {
    if (badges.isEmpty) return Future.value();

    // 播放徽章解锁音效
    SoundService.playBadgeUnlock();

    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      useSafeArea: true,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: BatchBadgeUnlockDialog(badges: badges),
      ),
    );
  }

  @override
  State<BatchBadgeUnlockDialog> createState() => _BatchBadgeUnlockDialogState();
}

class _BatchBadgeUnlockDialogState extends State<BatchBadgeUnlockDialog>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).chain(CurveTween(curve: Curves.easeOutBack)).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeCount = widget.badges.length;
    final primaryColor = widget.badges.first.color;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 320,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: -5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题
                  Text(
                    badgeCount == 1 ? '解锁新徽章！' : '解锁 $badgeCount 个新徽章！',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 徽章列表
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.badges.asMap().entries.map((entry) {
                          final index = entry.key;
                          final badge = entry.value;
                          return _buildBadgeItem(badge, index);
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 确定按钮
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('太棒了！'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadgeItem(Badge badge, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: badge.color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  badge.color.withValues(alpha: 0.9),
                  badge.color.withValues(alpha: 0.5),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                badge.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: badge.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4A4A6A),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
