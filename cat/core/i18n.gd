extends Node

# Internationalization (i18n) System
# Manages translations for multiple languages

# Signal emitted when language changes
signal language_changed(new_language: int)

enum Language {
	ENGLISH,
	JAPANESE,
	CHINESE,
	HINDI,
	SPANISH
}

# Current language
var current_language: Language = Language.ENGLISH

# Flag atlas mapping for language selector UI
# Maps Language enum to flag name in the atlas
var language_flags: Dictionary = {
	Language.ENGLISH: "british",        # or "americaflag"
	Language.JAPANESE: "japon",
	Language.CHINESE: "china",
	Language.HINDI: "India",
	Language.SPANISH: "spain"
}

# Which atlas to use for each flag
# realcountries.png = british, japon, china, spain
# realcountries2.png = India
var flag_atlas_mapping: Dictionary = {
	"british": "realcountries",
	"americaflag": "realcountries",
	"japon": "realcountries",
	"china": "realcountries",
	"spain": "realcountries",
	"India": "realcountries2"
}

# Hardcoded flag frame data (from realcountriesjson.json and realcountries2json.json)
# This avoids the need to load JSON files at runtime (fixes web build issues)
# Each flag has: x, y, w (width), h (height) in the atlas texture
var flag_frame_data: Dictionary = {
	"british": {"x": 91, "y": 1, "w": 16, "h": 32},
	"japon": {"x": 73, "y": 69, "w": 16, "h": 32},
	"china": {"x": 1, "y": 35, "w": 16, "h": 32},
	"spain": {"x": 1, "y": 103, "w": 16, "h": 32},
	"India": {"x": 1, "y": 1, "w": 16, "h": 32}  # From realcountries2
}

# Translation dictionary
# Structure: translations[key][language] = translated_string
var translations: Dictionary = {
	# UI - General
	"ui.close": {
		Language.ENGLISH: "Close",
		Language.JAPANESE: "閉じる",
		Language.CHINESE: "关闭",
		Language.HINDI: "बंद करें",
		Language.SPANISH: "Cerrar"
	},

	# UI - Hand/Cards
	"ui.hand.swap": {
		Language.ENGLISH: "Swap",
		Language.JAPANESE: "交換",
		Language.CHINESE: "交换",
		Language.HINDI: "अदला-बदली",
		Language.SPANISH: "Intercambiar"
	},
	"ui.hand.full": {
		Language.ENGLISH: "Hand is full! Use a card to draw more.",
		Language.JAPANESE: "手札が満杯です！カードを使用してください。",
		Language.CHINESE: "手牌已满！使用一张牌来抽更多牌。",
		Language.HINDI: "हाथ भरा है! अधिक कार्ड खींचने के लिए एक कार्ड का उपयोग करें।",
		Language.SPANISH: "¡La mano está llena! Usa una carta para robar más."
	},
	"ui.hand.drew": {
		Language.ENGLISH: "Drew: %s",
		Language.JAPANESE: "引いた: %s",
		Language.CHINESE: "抽取: %s",
		Language.HINDI: "खींचा: %s",
		Language.SPANISH: "Robó: %s"
	},
	"ui.hand.deck_empty": {
		Language.ENGLISH: "Deck is empty!",
		Language.JAPANESE: "デッキが空です！",
		Language.CHINESE: "牌组为空！",
		Language.HINDI: "डेक खाली है!",
		Language.SPANISH: "¡El mazo está vacío!"
	},
	"ui.hand.card_placed": {
		Language.ENGLISH: "Placed: %s",
		Language.JAPANESE: "配置: %s",
		Language.CHINESE: "放置: %s",
		Language.HINDI: "रखा: %s",
		Language.SPANISH: "Colocó: %s"
	},
	"ui.hand.tile_occupied": {
		Language.ENGLISH: "Tile is occupied!",
		Language.JAPANESE: "タイルは占有されています！",
		Language.CHINESE: "格子已被占用！",
		Language.HINDI: "टाइल पहले से भरी हुई है!",
		Language.SPANISH: "¡La casilla está ocupada!"
	},
	"ui.hand.joker_requires_water": {
		Language.ENGLISH: "Viking joker must be placed on water!",
		Language.JAPANESE: "バイキングジョーカーは水上に置く必要があります！",
		Language.CHINESE: "维京牌必须放在水上！",
		Language.HINDI: "वाइकिंग जोकर को पानी पर रखा जाना चाहिए!",
		Language.SPANISH: "¡El comodín vikingo debe colocarse en agua!"
	},
	"ui.hand.joker_requires_land": {
		Language.ENGLISH: "Dino joker must be placed on land!",
		Language.JAPANESE: "ディノジョーカーは陸上に置く必要があります！",
		Language.CHINESE: "恐龙牌必须放在陆地上！",
		Language.HINDI: "डायनो जोकर को जमीन पर रखा जाना चाहिए!",
		Language.SPANISH: "¡El comodín dino debe colocarse en tierra!"
	},
	"ui.hand.hint_place_card": {
		Language.ENGLISH: "Double click or tap to place",
		Language.JAPANESE: "ダブルクリックまたはタップして配置",
		Language.CHINESE: "双击或点击放置",
		Language.HINDI: "रखने के लिए डबल क्लिक या टैप करें",
		Language.SPANISH: "Doble clic o toca para colocar"
	},

	# HUD - Timer and Turns
	"ui.hud.timer": {
		Language.ENGLISH: "Timer: %ds",
		Language.JAPANESE: "タイマー: %d秒",
		Language.CHINESE: "计时器: %d秒",
		Language.HINDI: "समय: %dसे",
		Language.SPANISH: "Tiempo: %ds"
	},
	"ui.hud.turn": {
		Language.ENGLISH: "Turn: %d",
		Language.JAPANESE: "ターン: %d",
		Language.CHINESE: "回合: %d",
		Language.HINDI: "मोड़: %d",
		Language.SPANISH: "Turno: %d"
	},

	# Cards - Standard Suits
	"card.suit.clubs": {
		Language.ENGLISH: "Clubs",
		Language.JAPANESE: "クラブ",
		Language.CHINESE: "梅花",
		Language.HINDI: "चिड़ी",
		Language.SPANISH: "Tréboles"
	},
	"card.suit.diamonds": {
		Language.ENGLISH: "Diamonds",
		Language.JAPANESE: "ダイヤ",
		Language.CHINESE: "方块",
		Language.HINDI: "ईंट",
		Language.SPANISH: "Diamantes"
	},
	"card.suit.hearts": {
		Language.ENGLISH: "Hearts",
		Language.JAPANESE: "ハート",
		Language.CHINESE: "红心",
		Language.HINDI: "पान",
		Language.SPANISH: "Corazones"
	},
	"card.suit.spades": {
		Language.ENGLISH: "Spades",
		Language.JAPANESE: "スペード",
		Language.CHINESE: "黑桃",
		Language.HINDI: "हुकुम",
		Language.SPANISH: "Picas"
	},

	# Cards - Values
	"card.value.ace": {
		Language.ENGLISH: "Ace",
		Language.JAPANESE: "エース",
		Language.CHINESE: "A",
		Language.HINDI: "इक्का",
		Language.SPANISH: "As"
	},
	"card.value.jack": {
		Language.ENGLISH: "Jack",
		Language.JAPANESE: "ジャック",
		Language.CHINESE: "J",
		Language.HINDI: "गुलाम",
		Language.SPANISH: "Jota"
	},
	"card.value.queen": {
		Language.ENGLISH: "Queen",
		Language.JAPANESE: "クイーン",
		Language.CHINESE: "Q",
		Language.HINDI: "बेगम",
		Language.SPANISH: "Reina"
	},
	"card.value.king": {
		Language.ENGLISH: "King",
		Language.JAPANESE: "キング",
		Language.CHINESE: "K",
		Language.HINDI: "बादशाह",
		Language.SPANISH: "Rey"
	},

	# Cards - Custom
	"card.custom.viking": {
		Language.ENGLISH: "Vikings Special",
		Language.JAPANESE: "バイキング特別",
		Language.CHINESE: "维京特殊",
		Language.HINDI: "वाइकिंग विशेष",
		Language.SPANISH: "Vikingos Especial"
	},
	"card.custom.dino": {
		Language.ENGLISH: "Dino Special",
		Language.JAPANESE: "恐竜特別",
		Language.CHINESE: "恐龙特殊",
		Language.HINDI: "डायनो विशेष",
		Language.SPANISH: "Dino Especial"
	},
	"card.custom.generic": {
		Language.ENGLISH: "Custom Card",
		Language.JAPANESE: "カスタムカード",
		Language.CHINESE: "自定义卡牌",
		Language.HINDI: "कस्टम कार्ड",
		Language.SPANISH: "Carta Personalizada"
	},
	"card.of": {
		Language.ENGLISH: "of",
		Language.JAPANESE: "の",
		Language.CHINESE: "",
		Language.HINDI: "का",
		Language.SPANISH: "de"
	},

	# Entity Names
	"entity.viking.name": {
		Language.ENGLISH: "Viking Ship",
		Language.JAPANESE: "バイキング船",
		Language.CHINESE: "维京船",
		Language.HINDI: "वाइकिंग जहाज",
		Language.SPANISH: "Barco Vikingo"
	},
	"entity.jezza.name": {
		Language.ENGLISH: "Jezza",
		Language.JAPANESE: "ジェザ",
		Language.CHINESE: "杰扎",
		Language.HINDI: "जेज़ा",
		Language.SPANISH: "Jezza"
	},
	"entity.raptor": {
		Language.ENGLISH: "Raptor",
		Language.JAPANESE: "ラプター",
		Language.CHINESE: "迅猛龙",
		Language.HINDI: "रैप्टर",
		Language.SPANISH: "Raptor"
	},
	"entity.jezza_raptor": {
		Language.ENGLISH: "Jezza Raptor",
		Language.JAPANESE: "ジェザ・ラプター",
		Language.CHINESE: "杰扎迅猛龙",
		Language.HINDI: "जेज़ा रैप्टर",
		Language.SPANISH: "Jezza Raptor"
	},
	"entity.fantasy_warrior.name": {
		Language.ENGLISH: "Fantasy Warrior",
		Language.JAPANESE: "ファンタジーウォリアー",
		Language.CHINESE: "幻想战士",
		Language.HINDI: "काल्पनिक योद्धा",
		Language.SPANISH: "Guerrero Fantástico"
	},
	"entity.king.name": {
		Language.ENGLISH: "King",
		Language.JAPANESE: "王",
		Language.CHINESE: "国王",
		Language.HINDI: "राजा",
		Language.SPANISH: "Rey"
	},

	# Tile Types
	"tile.grassland": {
		Language.ENGLISH: "Grassland",
		Language.JAPANESE: "草原",
		Language.CHINESE: "草地",
		Language.HINDI: "घास का मैदान",
		Language.SPANISH: "Pradera"
	},
	"tile.water": {
		Language.ENGLISH: "Water",
		Language.JAPANESE: "水",
		Language.CHINESE: "水",
		Language.HINDI: "पानी",
		Language.SPANISH: "Agua"
	},
	"tile.city": {
		Language.ENGLISH: "City",
		Language.JAPANESE: "都市",
		Language.CHINESE: "城市",
		Language.HINDI: "शहर",
		Language.SPANISH: "Ciudad"
	},
	"tile.village": {
		Language.ENGLISH: "Village",
		Language.JAPANESE: "村",
		Language.CHINESE: "村庄",
		Language.HINDI: "गाँव",
		Language.SPANISH: "Pueblo"
	},

	# Tile Info UI Labels
	"tile_info.title": {
		Language.ENGLISH: "Tile Info",
		Language.JAPANESE: "タイル情報",
		Language.CHINESE: "地块信息",
		Language.HINDI: "टाइल जानकारी",
		Language.SPANISH: "Info del Mosaico"
	},
	"tile_info.coords": {
		Language.ENGLISH: "Coords",
		Language.JAPANESE: "座標",
		Language.CHINESE: "坐标",
		Language.HINDI: "निर्देशांक",
		Language.SPANISH: "Coords"
	},
	"tile_info.type": {
		Language.ENGLISH: "Type",
		Language.JAPANESE: "種類",
		Language.CHINESE: "类型",
		Language.HINDI: "प्रकार",
		Language.SPANISH: "Tipo"
	},
	"tile_info.world": {
		Language.ENGLISH: "World",
		Language.JAPANESE: "ワールド",
		Language.CHINESE: "世界",
		Language.HINDI: "विश्व",
		Language.SPANISH: "Mundo"
	},
	"tile_info.card": {
		Language.ENGLISH: "Card",
		Language.JAPANESE: "カード",
		Language.CHINESE: "卡牌",
		Language.HINDI: "कार्ड",
		Language.SPANISH: "Carta"
	},
	"tile_info.ulid": {
		Language.ENGLISH: "ULID",
		Language.JAPANESE: "ULID",
		Language.CHINESE: "ULID",
		Language.HINDI: "ULID",
		Language.SPANISH: "ULID"
	},

	# Entities - Flavor Text
	"entity.viking.flavor": {
		Language.ENGLISH: "Fearless raiders from the frozen north. Their longships cut through waves like axes through ice. They seek glory, plunder, and a place in Valhalla.",
		Language.JAPANESE: "凍てつく北の地から来た恐れ知らずの略奪者。彼らの長船は、氷を切る斧のように波を切り裂く。彼らは栄光、略奪品、そしてヴァルハラでの居場所を求めている。",
		Language.CHINESE: "来自冰冻北方的无畏掠夺者。他们的长船像斧头切冰一样劈开波浪。他们寻求荣耀、掠夺品和瓦尔哈拉的位置。",
		Language.HINDI: "जमे हुए उत्तर से निडर हमलावर। उनकी लंबी नावें बर्फ के माध्यम से कुल्हाड़ी की तरह लहरों को काटती हैं। वे महिमा, लूट और वलहैला में एक स्थान की तलाश करते हैं।",
		Language.SPANISH: "Intrépidos asaltantes del norte helado. Sus drakkars cortan las olas como hachas atraviesan el hielo. Buscan gloria, botín y un lugar en el Valhalla."
	},
	"entity.jezza.flavor": {
		Language.ENGLISH: "Ancient reptilian survivors from a forgotten age. Their roar echoes across time itself. Despite their fearsome appearance, they're surprisingly curious.",
		Language.JAPANESE: "忘れられた時代から生き残った古代の爬虫類。彼らの咆哮は時間そのものに響き渡る。恐ろしい外見にもかかわらず、彼らは驚くほど好奇心旺盛だ。",
		Language.CHINESE: "来自被遗忘时代的古老爬行动物幸存者。它们的咆哮穿越时间本身。尽管外表可怕，但它们出奇地好奇。",
		Language.HINDI: "भुला दिए गए युग के प्राचीन सरीसृप जीवित बचे। उनकी दहाड़ समय के माध्यम से गूंजती है। उनके भयानक रूप के बावजूद, वे आश्चर्यजनक रूप से जिज्ञासु हैं।",
		Language.SPANISH: "Antiguos sobrevivientes reptilianos de una era olvidada. Su rugido resuena a través del tiempo mismo. A pesar de su apariencia temible, son sorprendentemente curiosos."
	},
	"entity.fantasy_warrior.flavor": {
		Language.ENGLISH: "A legendary warrior from mystical realms. Master of blade and magic, they stride through battlefields with unmatched grace. Their courage inspires allies and strikes fear into enemies.",
		Language.JAPANESE: "神秘的な領域から来た伝説の戦士。剣と魔法の達人であり、比類のない優雅さで戦場を闊歩する。彼らの勇気は味方を鼓舞し、敵に恐怖を与える。",
		Language.CHINESE: "来自神秘领域的传奇战士。精通剑术和魔法，以无与伦比的优雅姿态穿越战场。他们的勇气激励盟友，令敌人恐惧。",
		Language.HINDI: "रहस्यमय क्षेत्रों से आया एक पौराणिक योद्धा। तलवार और जादू के मास्टर, वे अद्वितीय सुंदरता के साथ युद्धक्षेत्र में चलते हैं। उनकी साहस सहयोगियों को प्रेरित करती है और दुश्मनों में डर पैदा करती है।",
		Language.SPANISH: "Un guerrero legendario de reinos místicos. Maestro de la espada y la magia, atraviesa campos de batalla con gracia incomparable. Su valentía inspira a aliados y siembra terror en enemigos."
	},
	"entity.king.flavor": {
		Language.ENGLISH: "A noble ruler from a distant kingdom. Bearer of the crown and defender of the realm, he commands respect with wisdom and strength. His presence on the battlefield turns the tide of war.",
		Language.JAPANESE: "遠い王国からの高貴な支配者。王冠の持ち主であり領域の守護者であり、知恵と力で尊敬を集める。戦場での彼の存在は戦争の流れを変える。",
		Language.CHINESE: "来自遥远王国的尊贵统治者。王冠的承载者和领域的守护者，他以智慧和力量赢得尊重。他在战场上的出现扭转了战争的局势。",
		Language.HINDI: "एक दूर के राज्य से एक महान शासक। मुकुट के धारक और क्षेत्र के रक्षक, वह ज्ञान और शक्ति से सम्मान प्राप्त करते हैं। युद्धक्षेत्र पर उनकी उपस्थिति युद्ध की दिशा बदल देती है।",
		Language.SPANISH: "Un noble gobernante de un reino distante. Portador de la corona y defensor del reino, comanda respeto con sabiduría y fuerza. Su presencia en el campo de batalla cambia el curso de la guerra."
	},

	# Stats
	"stat.health": {
		Language.ENGLISH: "Health",
		Language.JAPANESE: "体力",
		Language.CHINESE: "生命值",
		Language.HINDI: "स्वास्थ्य",
		Language.SPANISH: "Salud"
	},
	"stat.attack": {
		Language.ENGLISH: "Attack",
		Language.JAPANESE: "攻撃力",
		Language.CHINESE: "攻击力",
		Language.HINDI: "हमला",
		Language.SPANISH: "Ataque"
	},
	"stat.defense": {
		Language.ENGLISH: "Defense",
		Language.JAPANESE: "防御力",
		Language.CHINESE: "防御力",
		Language.HINDI: "रक्षा",
		Language.SPANISH: "Defensa"
	},
	"stat.speed": {
		Language.ENGLISH: "Speed",
		Language.JAPANESE: "速度",
		Language.CHINESE: "速度",
		Language.HINDI: "गति",
		Language.SPANISH: "Velocidad"
	},
	"stat.range": {
		Language.ENGLISH: "Range",
		Language.JAPANESE: "射程",
		Language.CHINESE: "射程",
		Language.HINDI: "सीमा",
		Language.SPANISH: "Alcance"
	},
	"stat.morale": {
		Language.ENGLISH: "Morale",
		Language.JAPANESE: "士気",
		Language.CHINESE: "士气",
		Language.HINDI: "मनोबल",
		Language.SPANISH: "Moral"
	},
	"stat.level": {
		Language.ENGLISH: "Level",
		Language.JAPANESE: "レベル",
		Language.CHINESE: "等级",
		Language.HINDI: "स्तर",
		Language.SPANISH: "Nivel"
	},
	"stat.experience": {
		Language.ENGLISH: "Experience",
		Language.JAPANESE: "経験値",
		Language.CHINESE: "经验值",
		Language.HINDI: "अनुभव",
		Language.SPANISH: "Experiencia"
	},
	"stat.production_rate": {
		Language.ENGLISH: "Production Rate",
		Language.JAPANESE: "生産速度",
		Language.CHINESE: "生产速度",
		Language.HINDI: "उत्पादन दर",
		Language.SPANISH: "Tasa de Producción"
	},
	"stat.storage_capacity": {
		Language.ENGLISH: "Storage Capacity",
		Language.JAPANESE: "保管容量",
		Language.CHINESE: "存储容量",
		Language.HINDI: "भंडारण क्षमता",
		Language.SPANISH: "Capacidad de Almacenamiento"
	},

	# Resources
	"resource.gold": {
		Language.ENGLISH: "Gold",
		Language.JAPANESE: "ゴールド",
		Language.CHINESE: "金币",
		Language.HINDI: "सोना",
		Language.SPANISH: "Oro"
	},
	"resource.labor": {
		Language.ENGLISH: "Labor",
		Language.JAPANESE: "労働",
		Language.CHINESE: "劳工",
		Language.HINDI: "श्रम",
		Language.SPANISH: "Trabajo"
	},
	"resource.food": {
		Language.ENGLISH: "Food",
		Language.JAPANESE: "食料",
		Language.CHINESE: "食物",
		Language.HINDI: "भोजन",
		Language.SPANISH: "Comida"
	},
	"resource.wood": {
		Language.ENGLISH: "Wood",
		Language.JAPANESE: "木材",
		Language.CHINESE: "木材",
		Language.HINDI: "लकड़ी",
		Language.SPANISH: "Madera"
	},
	"resource.stone": {
		Language.ENGLISH: "Stone",
		Language.JAPANESE: "石",
		Language.CHINESE: "石头",
		Language.HINDI: "पत्थर",
		Language.SPANISH: "Piedra"
	},
	"resource.iron": {
		Language.ENGLISH: "Iron",
		Language.JAPANESE: "鉄",
		Language.CHINESE: "铁",
		Language.HINDI: "लोहा",
		Language.SPANISH: "Hierro"
	},
	"resource.faith": {
		Language.ENGLISH: "Faith",
		Language.JAPANESE: "信仰",
		Language.CHINESE: "信仰",
		Language.HINDI: "विश्वास",
		Language.SPANISH: "Fe"
	},

	# Game Messages
	"game.welcome": {
		Language.ENGLISH: "Welcome to Cat!",
		Language.JAPANESE: "Catへようこそ！",
		Language.CHINESE: "欢迎来到Cat！",
		Language.HINDI: "Cat में आपका स्वागत है!",
		Language.SPANISH: "¡Bienvenido a Cat!"
	},
	"game.entities_spawned": {
		Language.ENGLISH: "Vikings and Jezza spawned!",
		Language.JAPANESE: "バイキングとジェザが出現しました！",
		Language.CHINESE: "维京人和杰扎已生成！",
		Language.HINDI: "वाइकिंग और जेज़ा उत्पन्न हुए!",
		Language.SPANISH: "¡Vikings y Jezza aparecieron!"
	},
	"game.timer.reset": {
		Language.ENGLISH: "Timer reset!",
		Language.JAPANESE: "タイマーリセット！",
		Language.CHINESE: "计时器重置！",
		Language.HINDI: "टाइमर रीसेट!",
		Language.SPANISH: "¡Temporizador reiniciado!"
	},

	# Errors
	"error.card.placement_failed": {
		Language.ENGLISH: "Failed to place card",
		Language.JAPANESE: "カードの配置に失敗しました",
		Language.CHINESE: "放置卡牌失败",
		Language.HINDI: "कार्ड रखने में विफल",
		Language.SPANISH: "Error al colocar carta"
	},

	# Rust-triggered messages
	"rust.pathfinding.started": {
		Language.ENGLISH: "Calculating path...",
		Language.JAPANESE: "経路を計算中...",
		Language.CHINESE: "计算路径中...",
		Language.HINDI: "मार्ग की गणना हो रही है...",
		Language.SPANISH: "Calculando ruta..."
	},
	"rust.pathfinding.completed": {
		Language.ENGLISH: "Path found!",
		Language.JAPANESE: "経路が見つかりました！",
		Language.CHINESE: "找到路径！",
		Language.HINDI: "मार्ग मिला!",
		Language.SPANISH: "¡Ruta encontrada!"
	},
	"rust.pathfinding.failed": {
		Language.ENGLISH: "No path available",
		Language.JAPANESE: "経路が見つかりません",
		Language.CHINESE: "无可用路径",
		Language.HINDI: "कोई मार्ग उपलब्ध नहीं",
		Language.SPANISH: "No hay ruta disponible"
	},
	"rust.card.placed": {
		Language.ENGLISH: "Card placed on board",
		Language.JAPANESE: "カードがボードに配置されました",
		Language.CHINESE: "卡牌已放置到棋盘上",
		Language.HINDI: "कार्ड बोर्ड पर रखा गया",
		Language.SPANISH: "Carta colocada en el tablero"
	},
	"rust.card.removed": {
		Language.ENGLISH: "Card removed from board",
		Language.JAPANESE: "カードがボードから削除されました",
		Language.CHINESE: "卡牌已从棋盘上移除",
		Language.HINDI: "कार्ड बोर्ड से हटाया गया",
		Language.SPANISH: "Carta retirada del tablero"
	},
	"rust.resource.insufficient": {
		Language.ENGLISH: "Insufficient resources",
		Language.JAPANESE: "リソースが不足しています",
		Language.CHINESE: "资源不足",
		Language.HINDI: "अपर्याप्त संसाधन",
		Language.SPANISH: "Recursos insuficientes"
	},
	"rust.error.generic": {
		Language.ENGLISH: "An error occurred",
		Language.JAPANESE: "エラーが発生しました",
		Language.CHINESE: "发生错误",
		Language.HINDI: "एक त्रुटि हुई",
		Language.SPANISH: "Ocurrió un error"
	},

	# Card Combos - Poker Hands
	"combo.high_card": {
		Language.ENGLISH: "High Card",
		Language.JAPANESE: "ハイカード",
		Language.CHINESE: "高牌",
		Language.HINDI: "उच्च कार्ड",
		Language.SPANISH: "Carta Alta"
	},
	"combo.one_pair": {
		Language.ENGLISH: "One Pair",
		Language.JAPANESE: "ワンペア",
		Language.CHINESE: "一对",
		Language.HINDI: "एक जोड़ी",
		Language.SPANISH: "Par"
	},
	"combo.two_pair": {
		Language.ENGLISH: "Two Pair",
		Language.JAPANESE: "ツーペア",
		Language.CHINESE: "两对",
		Language.HINDI: "दो जोड़े",
		Language.SPANISH: "Doble Par"
	},
	"combo.three_of_a_kind": {
		Language.ENGLISH: "Three of a Kind",
		Language.JAPANESE: "スリーカード",
		Language.CHINESE: "三条",
		Language.HINDI: "तीन समान",
		Language.SPANISH: "Trío"
	},
	"combo.straight": {
		Language.ENGLISH: "Straight",
		Language.JAPANESE: "ストレート",
		Language.CHINESE: "顺子",
		Language.HINDI: "सीधा",
		Language.SPANISH: "Escalera"
	},
	"combo.flush": {
		Language.ENGLISH: "Flush",
		Language.JAPANESE: "フラッシュ",
		Language.CHINESE: "同花",
		Language.HINDI: "फ्लश",
		Language.SPANISH: "Color"
	},
	"combo.full_house": {
		Language.ENGLISH: "Full House",
		Language.JAPANESE: "フルハウス",
		Language.CHINESE: "葫芦",
		Language.HINDI: "फुल हाउस",
		Language.SPANISH: "Full"
	},
	"combo.four_of_a_kind": {
		Language.ENGLISH: "Four of a Kind",
		Language.JAPANESE: "フォーカード",
		Language.CHINESE: "四条",
		Language.HINDI: "चार समान",
		Language.SPANISH: "Póker"
	},
	"combo.straight_flush": {
		Language.ENGLISH: "Straight Flush",
		Language.JAPANESE: "ストレートフラッシュ",
		Language.CHINESE: "同花顺",
		Language.HINDI: "स्ट्रेट फ्लश",
		Language.SPANISH: "Escalera de Color"
	},
	"combo.royal_flush": {
		Language.ENGLISH: "Royal Flush",
		Language.JAPANESE: "ロイヤルフラッシュ",
		Language.CHINESE: "皇家同花顺",
		Language.HINDI: "रॉयल फ्लश",
		Language.SPANISH: "Escalera Real"
	},

	# Combo Messages
	"combo.detected": {
		Language.ENGLISH: "Combo Found!",
		Language.JAPANESE: "コンボ発見！",
		Language.CHINESE: "发现组合！",
		Language.HINDI: "कॉम्बो मिला!",
		Language.SPANISH: "¡Combo Encontrado!"
	},
	"combo.no_combo": {
		Language.ENGLISH: "No combo detected",
		Language.JAPANESE: "コンボが見つかりません",
		Language.CHINESE: "未检测到组合",
		Language.HINDI: "कोई कॉम्बो नहीं मिला",
		Language.SPANISH: "No se detectó combo"
	},
	"combo.resources_gained": {
		Language.ENGLISH: "Resources Gained:",
		Language.JAPANESE: "獲得リソース:",
		Language.CHINESE: "获得资源：",
		Language.HINDI: "प्राप्त संसाधन:",
		Language.SPANISH: "Recursos Obtenidos:"
	}
}

func _ready() -> void:
	# Load saved language preference
	var saved_language = _load_language_preference()
	if saved_language != -1:
		current_language = saved_language

	print("I18n: Initialized with language: %s" % _get_language_name(current_language))

## Get translated string by key
## Returns the English version if key or language not found
func translate(key: String, format_args: Array = []) -> String:
	if not translations.has(key):
		push_warning("I18n: Missing translation key: %s" % key)
		return key

	var lang_dict = translations[key]
	if not lang_dict.has(current_language):
		push_warning("I18n: Missing translation for language %s, key: %s" % [_get_language_name(current_language), key])
		# Fallback to English
		if lang_dict.has(Language.ENGLISH):
			var text = lang_dict[Language.ENGLISH]
			return text % format_args if format_args.size() > 0 else text
		return key

	var text = lang_dict[current_language]

	# Apply string formatting if format_args provided
	if format_args.size() > 0:
		return text % format_args

	return text

## Set current language (does NOT save to disk - temporary per session)
func set_language(language: Language) -> void:
	current_language = language
	# Don't save preference - language selector shows every time
	print("I18n: Language changed to: %s" % _get_language_name(language))
	# Emit signal to notify UI components to refresh
	language_changed.emit(language)

## Get current language
func get_current_language() -> Language:
	return current_language

## Get language name as string
func _get_language_name(language: Language) -> String:
	match language:
		Language.ENGLISH: return "English"
		Language.JAPANESE: return "日本語"
		Language.CHINESE: return "中文"
		Language.HINDI: return "हिन्दी"
		Language.SPANISH: return "Español"
	return "Unknown"

## Get all available languages
func get_available_languages() -> Array[Language]:
	return [
		Language.ENGLISH,
		Language.JAPANESE,
		Language.CHINESE,
		Language.HINDI,
		Language.SPANISH
	]

## Get language name for display in UI
func get_language_display_name(language: Language) -> String:
	return _get_language_name(language)

## Check if a translation key exists
func has_key(key: String) -> bool:
	return translations.has(key)

## Add or update a translation at runtime
func add_translation(key: String, lang: Language, text: String) -> void:
	if not translations.has(key):
		translations[key] = {}
	translations[key][lang] = text

## Get flag name for a language
func get_language_flag(language: Language) -> String:
	return language_flags.get(language, "british")

## Get atlas name for a flag
func get_flag_atlas(flag_name: String) -> String:
	return flag_atlas_mapping.get(flag_name, "realcountries")

## Get flag info for language selector (returns {flag: String, atlas: String})
func get_flag_info(language: Language) -> Dictionary:
	var flag_name = get_language_flag(language)
	var atlas_name = get_flag_atlas(flag_name)
	return {
		"flag": flag_name,
		"atlas": atlas_name
	}

## Get hardcoded flag frame data (returns Rect2 or null if not found)
## Avoids needing to load JSON files at runtime
func get_flag_frame(flag_name: String) -> Rect2:
	var frame_data = flag_frame_data.get(flag_name)
	if frame_data:
		return Rect2(
			frame_data["x"],
			frame_data["y"],
			frame_data["w"],
			frame_data["h"]
		)
	push_error("I18n: Flag frame data not found for: %s" % flag_name)
	return Rect2(0, 0, 16, 32)  # Default fallback

## Save language preference to user settings
func _save_language_preference(language: Language) -> void:
	var config = ConfigFile.new()
	config.set_value("i18n", "language", language)
	var err = config.save("user://i18n_settings.cfg")
	if err != OK:
		push_warning("I18n: Failed to save language preference")

## Load language preference from user settings
func _load_language_preference() -> int:
	var config = ConfigFile.new()
	var err = config.load("user://i18n_settings.cfg")
	if err != OK:
		return -1  # No saved preference
	return config.get_value("i18n", "language", -1)

## Helper: Get combo name in current language from Rust hand_name string
func get_combo_name(hand_name: String) -> String:
	var key_map = {
		"High Card": "combo.high_card",
		"One Pair": "combo.one_pair",
		"Two Pair": "combo.two_pair",
		"Three of a Kind": "combo.three_of_a_kind",
		"Straight": "combo.straight",
		"Flush": "combo.flush",
		"Full House": "combo.full_house",
		"Four of a Kind": "combo.four_of_a_kind",
		"Straight Flush": "combo.straight_flush",
		"Royal Flush": "combo.royal_flush"
	}

	var key = key_map.get(hand_name, "")
	if key.is_empty():
		return hand_name  # Return original if not found

	return translate(key)

## Helper: Get card name (suit + value) in current language
func get_card_name(suit: int, value: int, is_custom: bool = false) -> String:
	if is_custom:
		if value == 52:
			return tr("card.custom.viking")
		elif value == 53:
			return tr("card.custom.dino")
		return "Custom Card %d" % value

	# Standard card
	var suit_keys = ["card.suit.clubs", "card.suit.diamonds", "card.suit.hearts", "card.suit.spades"]
	var suit_name = tr(suit_keys[suit]) if suit >= 0 and suit < 4 else "Unknown"

	var value_name: String
	if value == 1:
		value_name = tr("card.value.ace")
	elif value == 11:
		value_name = tr("card.value.jack")
	elif value == 12:
		value_name = tr("card.value.queen")
	elif value == 13:
		value_name = tr("card.value.king")
	else:
		value_name = str(value)

	# Format: "Value of Suit" (e.g., "Ace of Spades")
	if current_language == Language.JAPANESE:
		return "%sの%s" % [suit_name, value_name]
	elif current_language == Language.CHINESE:
		return "%s%s" % [suit_name, value_name]
	elif current_language == Language.HINDI:
		return "%s का %s" % [suit_name, value_name]
	else:
		# English, Spanish, and default
		return "%s of %s" % [value_name, suit_name]
