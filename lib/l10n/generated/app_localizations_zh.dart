// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get sylvakru => '森露';

  @override
  String get title => '标题';

  @override
  String get artist => '艺术家';

  @override
  String get album => '专辑';

  @override
  String get albumArtist => '专辑艺术家';

  @override
  String get genre => '流派';

  @override
  String get year => '年份';

  @override
  String get track => '音轨编号';

  @override
  String get disc => '碟号';

  @override
  String get lyrics => '歌词';

  @override
  String get folder => '文件夹';

  @override
  String get frequently => '最多播放';

  @override
  String get recently => '最近播放';

  @override
  String get recentlyAdded => '最近添加';

  @override
  String get artists => '艺术家';

  @override
  String get albums => '专辑';

  @override
  String get folders => '文件夹';

  @override
  String get songs => '所有歌曲';

  @override
  String get home => '主页';

  @override
  String get playlists => '歌单';

  @override
  String get language => '语言';

  @override
  String get playQueue => '播放列表';

  @override
  String get followSystem => '跟随系统';

  @override
  String get settings => '设置';

  @override
  String get reload => '重新加载';

  @override
  String get manageMusicFolder => '管理音乐文件夹';

  @override
  String get about => '关于';

  @override
  String get openSourceLicense => '开源许可证';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get sleepTimer => '定时关闭';

  @override
  String get pauseAfterCurrentTrack => '播完整首歌再关闭';

  @override
  String get vibration => '振动';

  @override
  String get library => '音乐库';

  @override
  String get select => '批量选择';

  @override
  String get sortSongs => '歌曲排序';

  @override
  String get delete => '删除';

  @override
  String get remove => '移除';

  @override
  String get createPlaylist => '创建歌单';

  @override
  String get smartPlaylistName => '智能歌单名称';

  @override
  String get smartPlaylistQuery => '关键词筛选';

  @override
  String get smartPlaylistNameExists => '同名歌单已存在';

  @override
  String get createSmartPlaylist => '创建智能歌单';

  @override
  String get smartPlaylist => '智能歌单';

  @override
  String get order => '顺序';

  @override
  String get reorder => '调整顺序';

  @override
  String songCount(int count) {
    return '$count 首';
  }

  @override
  String artistCount(int count) {
    return '$count 人';
  }

  @override
  String albumCount(int count) {
    return '$count 张';
  }

  @override
  String playlistCount(int count) {
    return '$count 个';
  }

  @override
  String folderCount(int count) {
    return '$count 个';
  }

  @override
  String settingCount(int count) {
    return '$count 项';
  }

  @override
  String fontCount(int count) {
    return '$count 种';
  }

  @override
  String get searchSongs => '搜索歌曲';

  @override
  String get searchArtists => '搜索艺术家';

  @override
  String get searchAlbums => '搜索专辑';

  @override
  String get searchPlaylists => '搜索歌单';

  @override
  String get searchLicenses => '搜索许可证';

  @override
  String get ascending => '升序';

  @override
  String get descending => '降序';

  @override
  String get pictureSize => '图片大小';

  @override
  String get large => '大';

  @override
  String get small => '小';

  @override
  String get view => '视图';

  @override
  String get list => '列表';

  @override
  String get grid => '网格';

  @override
  String get favorited => '喜欢';

  @override
  String get favorites => '我喜欢的';

  @override
  String get duration => '时长';

  @override
  String get times => '次数';

  @override
  String get loop => '列表循环';

  @override
  String get shuffle => '随机播放';

  @override
  String get repeat => '单曲循环';

  @override
  String get playAll => '播放全部';

  @override
  String get move2Top => '移至顶部';

  @override
  String get playNow => '现在播放';

  @override
  String get playNext => '下一首播放';

  @override
  String get add2Queue => '添加到播放列表';

  @override
  String get editMetadata => '编辑元数据';

  @override
  String get add2Playlist => '添加到歌单';

  @override
  String get added2Playlist => '已添加到歌单';

  @override
  String get selectAll => '全选';

  @override
  String get complete => '完成';

  @override
  String get continueMsg => '确认要继续吗?';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get addFolder => '添加文件夹';

  @override
  String get addRecursiveFolder => '添加文件夹及所有子文件夹';

  @override
  String get replacePicture => '替换图片';

  @override
  String get unknown => '未知';

  @override
  String get updateMedata => '更新元数据';

  @override
  String get defaultText => '默认';

  @override
  String get titleAscending => '标题升序';

  @override
  String get titleDescending => '标题降序';

  @override
  String get artistAscending => '艺术家升序';

  @override
  String get artistDescending => '艺术家降序';

  @override
  String get albumAscending => '专辑升序';

  @override
  String get albumDescending => '专辑降序';

  @override
  String get durationAscending => '时长升序';

  @override
  String get durationDescending => '时长降序';

  @override
  String get selectSortingType => '选择排序类型';

  @override
  String get loadingFolder => '正在加载的文件夹';

  @override
  String get loadedSongs => '已加载歌曲';

  @override
  String get loadingNavidrome => '正在加载Navidrome';

  @override
  String get canNotUpdate => '无法修改正在播放的歌曲';

  @override
  String get updateSuccessfully => '更新成功';

  @override
  String get updateFailed => '更新失败';

  @override
  String get clear => '清空';

  @override
  String get reset => '重置';

  @override
  String get desktopLyrics => '桌面歌词';

  @override
  String get horizontal => '水平';

  @override
  String get vertical => '竖直';

  @override
  String get lock => '锁定';

  @override
  String get unlock => '解锁';

  @override
  String get closeAction => '关闭动作';

  @override
  String get exit => '退出';

  @override
  String get hide => '隐藏';

  @override
  String get checkUpdate => '检查更新';

  @override
  String get go2Download => '前往下载';

  @override
  String get alreadyLatest => '已经是最新版本';

  @override
  String get theme => '主题';

  @override
  String get mainPageTheme => '主页面主题';

  @override
  String get lyricsPageTheme => '歌词页面主题';

  @override
  String get vividMode => '生动模式';

  @override
  String get lightMode => '浅色模式';

  @override
  String get darkMode => '深色模式';

  @override
  String get customMode => '自定义模式';

  @override
  String get local => '本地';

  @override
  String get switchSource => '切换音乐来源';

  @override
  String get manageServers => '管理服务器';

  @override
  String get username => '账号';

  @override
  String get password => '密码';

  @override
  String get exportLog => '导出日志';

  @override
  String get showApp => '显示应用';

  @override
  String get skip2Previous => '上一首';

  @override
  String get skip2Next => '下一首';

  @override
  String get playOrPause => '播放/暂停';

  @override
  String get unlockDeskLrc => '解锁桌面歌词';

  @override
  String get autoPlayOnStartup => '启动后自动播放';

  @override
  String get return2Previous => '返回上一级';

  @override
  String get addedFolders => '已添加的目录';

  @override
  String get recursiveScan => '扫描子目录';

  @override
  String get songInfo => '歌曲信息';

  @override
  String get format => '格式';

  @override
  String get bitrate => '比特率';

  @override
  String get samplerate => '采样率';

  @override
  String get filePath => '文件路径';

  @override
  String get path => '路径';

  @override
  String get go2Artist => '查看艺术家';

  @override
  String get go2Album => '查看专辑';

  @override
  String get equalizer => '均衡器';

  @override
  String get more => '更多';

  @override
  String get randomize => '随机';

  @override
  String get normal => '正常';

  @override
  String get randomizeTemp => '随机(暂时)';

  @override
  String get randomizePermanent => '随机(永久)';

  @override
  String get modifiedTimeAscending => '修改时间升序';

  @override
  String get modifiedTimedescending => '修改时间降序';

  @override
  String get playQueueEmpty => '播放队列是空的';

  @override
  String get cannotBeUndone => '不可撤销';

  @override
  String get clearCache => '清除临时缓存';

  @override
  String get offlineMusicLimit => '下载上限';

  @override
  String get offlineMusicLimitUnlimited => '不限制';

  @override
  String get cache => '临时缓存';

  @override
  String get cacheUsage => '临时缓存占用';

  @override
  String get temporaryCacheDescription => '播放时自动保存的音频，可随时清理，不影响已下载的音乐';

  @override
  String get offlineMusicStorage => '下载占用';

  @override
  String get tapAgain => '再按一次退出';

  @override
  String get close => '关闭';

  @override
  String get fonts => '字体';

  @override
  String get searchFonts => '搜索字体';

  @override
  String get setFontName => '设置字体名称';

  @override
  String get setFont => '设置字体';

  @override
  String get restoreDefault => '恢复默认';

  @override
  String get addFont => '添加字体';

  @override
  String get deleteFont => '删除字体';

  @override
  String get currentFont => '当前字体';

  @override
  String get refresh => '刷新';

  @override
  String get syncLibrary => '同步资料库';

  @override
  String get syncingTryLater => '正在同步，请稍后再试';

  @override
  String get all => '全部';

  @override
  String get folderExist => '该文件夹已存在';

  @override
  String get folderNotSupportedYet => '暂不支持该文件夹';

  @override
  String get getPermissionFailed => '获取权限失败';

  @override
  String get premiumFeatures => '高级功能';

  @override
  String get premiumDescription => '获得更完整的使用体验并支持应用持续开发';

  @override
  String get unlockPremium => '解锁高级功能';

  @override
  String get restorePurchase => '恢复购买';

  @override
  String get whatPremiumContains => '高级功能包含';

  @override
  String get themeDescription => '支持开启主页面生动模式';

  @override
  String get fontDescription => '可使用自定义字体';

  @override
  String get equalizerDescription => '可调节不同频段的音量';

  @override
  String get futurePremium => '未来高级功能';

  @override
  String get futurePremiumDescription => '后续新增的高级功能自动解锁';

  @override
  String get premiumRequiredMessage => '当前功能需要解锁高级功能后才能使用';

  @override
  String get premiumUnlockHint => '请前往「设置 > 高级功能」进行解锁';

  @override
  String get alreadyPremium => '已解锁高级功能';

  @override
  String get pendingPurchase => '正在处理中...';

  @override
  String get purchaseNotFound => '未发现购买记录';

  @override
  String get productNotAvailable => '无法获取商品信息，请检查网络连接后重试';

  @override
  String get iapNotAvailable => '应用内购买功能暂不可用, 请稍后再试';

  @override
  String get connectingToAppStore => '正在连接 App Store...';

  @override
  String get checkingPurchase => '正在检查购买记录...';

  @override
  String get noLyrics => '暂无歌词';

  @override
  String get lyricsParseFailed => '歌词解析失败';

  @override
  String get switchMode => '切换模式';

  @override
  String get viewLog => '查看日志';

  @override
  String get premiumTrialActive => '高级功能试用已开启';

  @override
  String trialRemainingStatus(int count) {
    return '剩余试用时间：$count 分钟\n试用结束后, 购买高级功能即可继续使用';
  }

  @override
  String get gotIt => '好的';

  @override
  String get trialRemaining => '剩余试用时间';

  @override
  String get bigPictureMode => '大图模式';

  @override
  String get bigPictureModeDescription => '解锁大图模式';

  @override
  String get adjustLyrics => '调整歌词';

  @override
  String get fontSize => '字体大小';

  @override
  String get fontWeight => '字体粗细';

  @override
  String get offset => '偏移';

  @override
  String get getStart => '开始使用';

  @override
  String get immersiveWideLayout => '宽布局启用沉浸模式';

  @override
  String get menuOnRight => '从右侧弹出菜单';

  @override
  String get save => '保存';

  @override
  String get chooseMusicSource => '选择音乐来源';

  @override
  String get feiniuMusic => '飞牛音乐';

  @override
  String get feiniuServerAddress => 'URL / FN ID';

  @override
  String get feiniuNasLogin => '通过 NAS 账号登录';

  @override
  String get feiniuNasLoginFailed => 'NAS 授权登录未完成，请检查地址并重试。';

  @override
  String get feiniuConnectionFailed => '无法连接飞牛音乐，请检查服务器地址及音乐应用账号密码';

  @override
  String get savedSuccessfully => '保存成功';

  @override
  String get biography => '简介';

  @override
  String get showMore => '展开';

  @override
  String get showLess => '收起';

  @override
  String get forYou => '为你推荐';

  @override
  String get recommendSongs => '推荐歌曲';

  @override
  String get recommendArtists => '推荐艺术家';

  @override
  String get recommendEmpty => '多听几首歌，这里就会出现为你推荐的音乐。';

  @override
  String reasonFavoriteArtist(String name) {
    return '因为你喜欢 $name';
  }

  @override
  String reasonSimilarGenre(String name) {
    return '更多 $name';
  }

  @override
  String get reasonRediscover => '好久没听了';

  @override
  String get reasonExplore => '换个口味';

  @override
  String reasonUnexplored(int count) {
    return '还有 $count 首没听过';
  }

  @override
  String get refreshRecommendations => '换一批';

  @override
  String get advancedSearch => '高级搜索';

  @override
  String get searchIn => '搜索范围';

  @override
  String get exactMatch => '精确匹配';

  @override
  String get yearRange => '年份';

  @override
  String get durationRangeSeconds => '时长（秒）';

  @override
  String get bitrateRangeKbps => '比特率（kbps）';

  @override
  String get minimum => '最小值';

  @override
  String get maximum => '最大值';

  @override
  String get applyFilters => '应用筛选';

  @override
  String get invalidRange => '请输入有效范围，最小值不能大于最大值';

  @override
  String get offlineMusic => '下载中心';

  @override
  String get offlineMusicDescription => '已下载到本地，可自定义下载目录，随时离线播放';

  @override
  String get noOfflineMusic => '暂无下载';

  @override
  String offlineMusicCount(int count) {
    return '$count 首下载';
  }

  @override
  String get downloadForOffline => '下载';

  @override
  String get removeDownload => '移除下载';

  @override
  String get downloading => '正在下载…';

  @override
  String get downloadFailed => '下载失败，请检查网络和存储空间';

  @override
  String get downloadInUse => '这首歌正在播放且没有下一首可切换，请先切歌再移除';

  @override
  String get downloadAll => '下载全部';

  @override
  String queuedForDownload(int count) {
    return '已加入下载队列（$count 首）';
  }

  @override
  String get downloadAllDone => '这些都已在下载中心';

  @override
  String get noOfflineMusicHint => '在歌曲菜单里选择「下载」，之后无网络也能播放';

  @override
  String get browseSongs => '去浏览音乐';

  @override
  String get playQueueEmptyHint => '在歌曲菜单里选择「添加到播放列表」，歌曲会出现在这里';

  @override
  String get musicSource => '音乐来源';

  @override
  String get appearance => '外观';

  @override
  String get playback => '播放';

  @override
  String get system => '系统';

  @override
  String get connectFailedWebdav => '无法连接 WebDAV';

  @override
  String get connectFailedNavidrome => '无法连接 Navidrome';

  @override
  String get connectFailedEmby => '无法连接 Emby';

  @override
  String get connectWebdavFirst => '请先连接 WebDAV';

  @override
  String get addedToPlayQueue => '已加入播放列表';

  @override
  String get currentSongNotFound => '找不到当前歌曲';

  @override
  String get fontNameConflict => '与系统字体同名';

  @override
  String exportTo(String path) {
    return '已导出到 $path';
  }

  @override
  String get downloadDirectory => '下载目录';

  @override
  String get downloadFolderDefault => '应用数据目录';

  @override
  String get chooseFolder => '选择';

  @override
  String get downloadsMigrateExisting => '迁移现有文件';

  @override
  String get downloadsNewOnly => '仅对新下载生效';

  @override
  String get otherFiles => '其它文件';

  @override
  String downloadsMoved(int count) {
    return '已迁移 $count 个文件';
  }

  @override
  String get downloadNaming => '下载命名';

  @override
  String get downloadNamingHash => '哈希名（与旧版本一致）';

  @override
  String get downloadNamingArtistTitle => '歌手 - 标题';

  @override
  String get downloadNamingArtistAlbumTrack => '歌手 / 专辑 / 序号 标题';

  @override
  String get downloadsRenameExisting => '重命名现有文件';

  @override
  String downloadsRenamed(int count) {
    return '已重命名 $count 个文件';
  }

  @override
  String get downloadTags => '下载后写入标签';

  @override
  String get downloadTagsDescription => '把歌名、歌手、专辑等写进下载的文件，离开本应用也能正常显示';

  @override
  String get downloadSettings => '下载';

  @override
  String get downloadTagsOn => '写入标签';

  @override
  String get downloadTagsOff => '不写标签';

  @override
  String get translation => '翻译';

  @override
  String get translationOff => '未启用';

  @override
  String get translationNotConfigured => '服务未配置';

  @override
  String get translationEnabled => '翻译艺术家简介';

  @override
  String get translationNotice => '译文由你填写的服务生成，简介原文会上传到该服务';

  @override
  String get translationBaseUrl => '接口地址';

  @override
  String get translationModel => '模型';

  @override
  String get translationApiKey => 'API Key';

  @override
  String get translationUnset => '未填写';

  @override
  String get translationKeySaved => '已保存';

  @override
  String get translationClearCache => '清空翻译缓存';

  @override
  String translationCachedCount(int count) {
    return '已缓存 $count 条译文';
  }

  @override
  String get translationCacheCleared => '翻译缓存已清空';

  @override
  String get translationShowOriginal => '显示原文';

  @override
  String get translationShowTranslated => '显示译文';

  @override
  String get translationProvider => '服务商';

  @override
  String get translationFormat => '接口格式';

  @override
  String get translationFormatChat => 'OpenAI Chat Completions';

  @override
  String get translationFormatExact => '完整接口地址';

  @override
  String get translationFormatExactHint => '地址已包含 /chat/completions，按原样请求';

  @override
  String get translationCustom => '自定义';

  @override
  String get translationModelCustom => '自定义模型…';

  @override
  String get translationTest => '测试连接';

  @override
  String get translationTestHint => '向服务发一条示例，确认地址、模型与 API Key 都可用';

  @override
  String get translationTestOk => '连接正常，服务已返回译文';

  @override
  String get translationTestFailed => '连接失败，请检查接口地址、模型与 API Key';

  @override
  String get revealInFolder => '在文件夹中显示';

  @override
  String get otherFilesEmpty => '没有其它文件';

  @override
  String get otherFilesHint => '这些文件不属于曲库，可逐个查看或删除';

  @override
  String get deleteFile => '删除文件';

  @override
  String get unknownArtist => '未知艺术家';

  @override
  String get unknownAlbum => '未知专辑';

  @override
  String get unknownAlbumArtist => '未知专辑艺术家';

  @override
  String get unknownGenre => '未知流派';

  @override
  String get sortBy => '排序';

  @override
  String get groupBy => '分组';

  @override
  String get selectSongs => '选择';

  @override
  String get sortTitle => '标题';

  @override
  String get sortArtist => '艺术家';

  @override
  String get sortAlbum => '专辑';

  @override
  String get sortRecentlyPlayed => '最近播放';

  @override
  String get sortMostPlayed => '最常播放';

  @override
  String get groupNone => '不分组';

  @override
  String get groupAlbum => '按专辑';

  @override
  String get groupArtist => '按艺术家';

  @override
  String get downloadCancel => '取消下载';

  @override
  String get downloadRetry => '重试';

  @override
  String get diskSpaceWarn => '磁盘余量提醒';

  @override
  String get diskSpaceWarnOff => '关闭';

  @override
  String get diskFreeSpace => '磁盘剩余';

  @override
  String get diskFreeSpaceUnknown => '未知';

  @override
  String diskSpaceLow(String free, String threshold) {
    return '磁盘剩余 $free，已低于提醒线 $threshold';
  }

  @override
  String diskSpaceLowQueued(int count, String free) {
    return '已加入下载队列（$count 首），磁盘剩余 $free';
  }
}
