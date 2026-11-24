import Foundation

// Response models of the Food API (v2). Parsing is lenient: fields the SDK doesn't know are ignored, missing optional
// fields get defaults, and enum values newer than the SDK parse as `.unknown`, so newer API versions keep working
// with older SDKs.

/// Whether a food is a generic food (an apple, cooked rice) or a branded product.
public enum FoodType: Sendable, Hashable, Codable, RawRepresentable {
    case generic
    case brand
    /// A type this version of the SDK doesn't know.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "generic": self = .generic
        case "brand": self = .brand
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .generic: "generic"
        case .brand: "brand"
        case .unknown(let value): value
        }
    }

    public init(from decoder: any Decoder) throws { self.init(rawValue: try decodeRawValue(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeRawValue(rawValue, encoder) }
}

/// Marks a nutrient value that isn't a plain measurement. A value without a flag is as precise as its source says
/// nothing otherwise.
public enum NutrientFlag: Sendable, Hashable, Codable, RawRepresentable {
    /// The label said "less than": the real amount is at most the value (show "< 1 g").
    case upperBound
    /// Rounded or estimated on the label, for example worked out from a % daily value.
    case approximate
    /// Set to 0 by the source without being measured.
    case assumedZero
    /// A flag this version of the SDK doesn't know.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "upper_bound": self = .upperBound
        case "approximate": self = .approximate
        case "assumed_zero": self = .assumedZero
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .upperBound: "upper_bound"
        case .approximate: "approximate"
        case .assumedZero: "assumed_zero"
        case .unknown(let value): value
        }
    }

    public init(from decoder: any Decoder) throws { self.init(rawValue: try decodeRawValue(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeRawValue(rawValue, encoder) }
}

/// How closely a food's image shows it.
public enum ImageMatch: Sendable, Hashable, Codable, RawRepresentable {
    /// This food in its form or flavour (whole milk, not just milk).
    case variant
    /// This food.
    case food
    /// The kind of food it is, for example cheese for a gouda.
    case category
    /// Nothing fitted, so a generic plate, drink or meal; apps may prefer to show none.
    case fallback
    /// A value this version of the SDK doesn't know: treat it like `.category`.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "variant": self = .variant
        case "food": self = .food
        case "category": self = .category
        case "fallback": self = .fallback
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .variant: "variant"
        case .food: "food"
        case .category: "category"
        case .fallback: "fallback"
        case .unknown(let value): value
        }
    }

    public init(from decoder: any Decoder) throws { self.init(rawValue: try decodeRawValue(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeRawValue(rawValue, encoder) }
}

/// How specific an image of the set is.
public enum ImageTier: Sendable, Hashable, Codable, RawRepresentable {
    /// A kind of food (cheese).
    case category
    /// One food (cheddar).
    case food
    /// A form of a food (whole milk).
    case variant
    /// A tier this version of the SDK doesn't know.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "category": self = .category
        case "food": self = .food
        case "variant": self = .variant
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .category: "category"
        case .food: "food"
        case .variant: "variant"
        case .unknown(let value): value
        }
    }

    public init(from decoder: any Decoder) throws { self.init(rawValue: try decodeRawValue(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeRawValue(rawValue, encoder) }
}

/// One food in the catalog, with its nutrition per serving.
public struct Food: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var brand: String?
    public var type: FoodType
    public var barcodes: [String]
    public var servings: [Serving]
    public var source: FoodSource
    /// What the source says about the food; nil when unknown.
    public var ingredients: String?
    public var category: String?
    /// Everything else the source gives about the food, as text. See `alternateNames`.
    public var attributes: [String: String]
    /// Nutrient values that aren't plain measurements, by nutrient key. They hold for every serving.
    public var nutrientFlags: [String: NutrientFlag]
    /// A picture of the food; nil in answers from before the API had images.
    public var image: FoodImage?

    public init(
        id: String,
        name: String,
        brand: String? = nil,
        type: FoodType,
        barcodes: [String] = [],
        servings: [Serving],
        source: FoodSource,
        ingredients: String? = nil,
        category: String? = nil,
        attributes: [String: String] = [:],
        nutrientFlags: [String: NutrientFlag] = [:],
        image: FoodImage? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.type = type
        self.barcodes = barcodes
        self.servings = servings
        self.source = source
        self.ingredients = ingredients
        self.category = category
        self.attributes = attributes
        self.nutrientFlags = nutrientFlags
        self.image = image
    }

    /// Other names the source gives the food ("pop", "soda" for cola).
    public var alternateNames: [String] {
        (attributes["alternate_names"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The flag of a nutrient value, or nil when it has none.
    public func flag(_ nutrient: String) -> NutrientFlag? { nutrientFlags[nutrient] }

    enum CodingKeys: String, CodingKey {
        case id, name, brand, type, barcodes, servings, source, ingredients, category, attributes, image
        case nutrientFlags = "nutrient_flags"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        type = try c.decodeIfPresent(FoodType.self, forKey: .type) ?? .unknown("")
        barcodes = try c.decodeIfPresent([String].self, forKey: .barcodes) ?? []
        servings = try c.decodeIfPresent([Serving].self, forKey: .servings) ?? []
        source = try c.decode(FoodSource.self, forKey: .source)
        ingredients = try c.decodeIfPresent(String.self, forKey: .ingredients)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        attributes =
            try c.decodeIfPresent([String: TextOrNothing].self, forKey: .attributes)?.compactMapValues(\.text) ?? [:]
        nutrientFlags =
            try c.decodeIfPresent([String: TextOrNothing].self, forKey: .nutrientFlags)?
            .compactMapValues { $0.text.map(NutrientFlag.init(rawValue:)) } ?? [:]
        // An image the SDK can't read is left out rather than failing the whole food
        image = (try? c.decodeIfPresent(FoodImage.self, forKey: .image)) ?? nil
    }
}

/// A picture of a food from the API's image set: a 256 px JPEG. The URL is public (it needs no API key) and never
/// changes for a key, so it can be cached for good.
public struct FoodImage: Sendable, Hashable, Codable {
    /// `group/slug`, as in `FoodAPIClient.images()` ("dairy/cheddar").
    public var key: String
    public var url: URL
    /// How closely the image shows the food.
    public var match: ImageMatch

    public init(key: String, url: URL, match: ImageMatch) {
        self.key = key
        self.url = url
        self.match = match
    }

    /// Whether this is the generic picture used when nothing fitted the food (a plate, a drink); apps may prefer to
    /// show none.
    public var isFallback: Bool { match == .fallback }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        url = try c.decode(URL.self, forKey: .url)
        match = try c.decodeIfPresent(ImageMatch.self, forKey: .match) ?? .unknown("")
    }
}

/// Where a food's data comes from (USDA, CNF, FatSecret, OpenFoodFacts) and its ID there.
public struct FoodSource: Sendable, Hashable, Codable {
    public var provider: String
    public var id: String

    public init(provider: String, id: String) {
        self.provider = provider
        self.id = id
    }
}

/// One way of measuring a food (a cup, 100 g, one bar), with the nutrients it contains.
public struct Serving: Sendable, Hashable, Codable {
    public var description: String
    public var measurement: String
    public var metricAmount: Double?
    public var metricUnit: String
    public var units: Double?
    public var nutrients: Nutrients
    /// The source's own ID for the serving, when it has one.
    public var sourceID: String?
    /// Whether the API worked this serving out from the source's ones (100 g, 1 oz, 1 fl oz, 1 cup, …). Generic
    /// servings come after the source's own.
    public var generic: Bool

    public init(
        description: String,
        measurement: String,
        metricAmount: Double? = nil,
        metricUnit: String,
        units: Double? = nil,
        nutrients: Nutrients,
        sourceID: String? = nil,
        generic: Bool = false
    ) {
        self.description = description
        self.measurement = measurement
        self.metricAmount = metricAmount
        self.metricUnit = metricUnit
        self.units = units
        self.nutrients = nutrients
        self.sourceID = sourceID
        self.generic = generic
    }

    enum CodingKeys: String, CodingKey {
        case description, measurement, units, nutrients, generic
        case metricAmount = "metric_amount"
        case metricUnit = "metric_unit"
        case sourceID = "source_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        measurement = try c.decodeIfPresent(String.self, forKey: .measurement) ?? ""
        metricAmount = try c.decodeIfPresent(Double.self, forKey: .metricAmount)
        metricUnit = try c.decodeIfPresent(String.self, forKey: .metricUnit) ?? ""
        units = try c.decodeIfPresent(Double.self, forKey: .units)
        nutrients = try c.decodeIfPresent(Nutrients.self, forKey: .nutrients) ?? Nutrients()
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID)
        generic = try c.decodeIfPresent(Bool.self, forKey: .generic) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(description, forKey: .description)
        try c.encode(measurement, forKey: .measurement)
        try c.encode(metricAmount, forKey: .metricAmount)
        try c.encode(metricUnit, forKey: .metricUnit)
        try c.encode(units, forKey: .units)
        try c.encode(nutrients, forKey: .nutrients)
        try c.encodeIfPresent(sourceID, forKey: .sourceID)
        if generic { try c.encode(true, forKey: .generic) }
    }
}

/// The core nutrient keys: every serving has them, nil when unknown. `FoodAPIClient.nutrients()` lists every key.
public enum NutrientKey {
    public static let calories = "calories"  // kcal
    public static let protein = "protein"  // g
    public static let carbohydrate = "carbohydrate"  // g
    public static let fat = "fat"  // g
    public static let sugar = "sugar"  // g
    public static let fiber = "fiber"  // g
    public static let saturatedFat = "saturated_fat"  // g
    public static let monounsaturatedFat = "monounsaturated_fat"  // g
    public static let polyunsaturatedFat = "polyunsaturated_fat"  // g
    public static let cholesterol = "cholesterol"  // mg
    public static let sodium = "sodium"  // mg
    public static let potassium = "potassium"  // mg
    public static let calcium = "calcium"  // mg
    public static let iron = "iron"  // mg
    public static let vitaminA = "vitamin_a"  // µg
    public static let vitaminC = "vitamin_c"  // mg
    public static let vitaminD = "vitamin_d"  // µg
}

/// A serving's nutrient amounts by key, in the units `FoodAPIClient.nutrients()` lists. The core nutrients have
/// properties and are nil when unknown; read any other key with `nutrients["magnesium"]`.
public struct Nutrients: Sendable, Hashable, Codable {
    /// Every nutrient the serving has a key for; a nil value means unknown.
    public var values: [String: Double?]

    public init(_ values: [String: Double?] = [:]) { self.values = values }

    /// The amount of a nutrient, or nil when unknown.
    public subscript(key: String) -> Double? { values[key] ?? nil }

    public var calories: Double? { self[NutrientKey.calories] }  // kcal
    public var protein: Double? { self[NutrientKey.protein] }  // g
    public var carbohydrate: Double? { self[NutrientKey.carbohydrate] }  // g
    public var fat: Double? { self[NutrientKey.fat] }  // g
    public var sugar: Double? { self[NutrientKey.sugar] }  // g
    public var fiber: Double? { self[NutrientKey.fiber] }  // g
    public var saturatedFat: Double? { self[NutrientKey.saturatedFat] }  // g
    public var monounsaturatedFat: Double? { self[NutrientKey.monounsaturatedFat] }  // g
    public var polyunsaturatedFat: Double? { self[NutrientKey.polyunsaturatedFat] }  // g
    public var cholesterol: Double? { self[NutrientKey.cholesterol] }  // mg
    public var sodium: Double? { self[NutrientKey.sodium] }  // mg
    public var potassium: Double? { self[NutrientKey.potassium] }  // mg
    public var calcium: Double? { self[NutrientKey.calcium] }  // mg
    public var iron: Double? { self[NutrientKey.iron] }  // mg
    public var vitaminA: Double? { self[NutrientKey.vitaminA] }  // µg
    public var vitaminC: Double? { self[NutrientKey.vitaminC] }  // mg
    public var vitaminD: Double? { self[NutrientKey.vitaminD] }  // µg

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var values: [String: Double?] = [:]
        for key in c.allKeys {
            values[key.stringValue] = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil
        }
        self.values = values
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in values {
            try c.encode(value, forKey: AnyKey(key))
        }
    }
}

/// One page of search results.
public struct SearchPage: Sendable, Hashable, Codable {
    public var foods: [Food]
    /// The query as searched: lowercase, single spaces.
    public var query: String
    public var page: Int
    public var limit: Int
    public var total: Int
    /// "catalog", or "provider" when the catalog had no good match and the results came from an outside provider.
    public var source: String
    /// With regional ranking, the country whose foods ranked first among equally good matches (an ISO code such as
    /// "CA"); nil when none did. The API finds the user's country from the device's address, so apps send nothing.
    public var region: String?
    /// Whether the API answered from its cache.
    public var cached: Bool

    public init(
        foods: [Food], query: String, page: Int, limit: Int, total: Int, source: String, region: String? = nil,
        cached: Bool
    ) {
        self.foods = foods
        self.query = query
        self.page = page
        self.limit = limit
        self.total = total
        self.source = source
        self.region = region
        self.cached = cached
    }
}

/// An autocomplete match: enough to show in a list. Look the food up with `FoodAPIClient.food(_:)` when picked.
public struct Suggestion: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var brand: String?

    public init(id: String, name: String, brand: String? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
    }
}

/// The suggestions for what has been typed so far.
public struct AutocompleteResult: Sendable, Hashable, Codable {
    public var suggestions: [Suggestion]
    public var query: String
    public var limit: Int
    /// How many foods match.
    public var total: Int
    public var cached: Bool

    public init(suggestions: [Suggestion], query: String, limit: Int, total: Int, cached: Bool) {
        self.suggestions = suggestions
        self.query = query
        self.limit = limit
        self.total = total
        self.cached = cached
    }
}

/// What a food's source says about each of its nutrient values, per 100 g.
public struct NutrientStats: Sendable, Hashable, Codable {
    public var foodID: String
    public var per: String
    public var nutrients: [String: NutrientStat]

    public init(foodID: String, per: String, nutrients: [String: NutrientStat]) {
        self.foodID = foodID
        self.per = per
        self.nutrients = nutrients
    }

    enum CodingKeys: String, CodingKey {
        case foodID = "id"
        case per, nutrients
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodID = try c.decode(String.self, forKey: .foodID)
        per = try c.decodeIfPresent(String.self, forKey: .per) ?? "100 g"
        nutrients = try c.decodeIfPresent([String: NutrientStat].self, forKey: .nutrients) ?? [:]
    }
}

/// How one nutrient value was obtained. Amounts are per 100 g.
public struct NutrientStat: Sendable, Hashable, Codable {
    /// Samples the value comes from.
    public var dataPoints: Int?
    public var stdError: Double?
    public var min: Double?
    public var max: Double?
    public var median: Double?
    /// The source's code for how the value was obtained, and what it means.
    public var derivation: String?
    public var derivationDescription: String?
    public var derivationBasis: String?
    public var footnote: String?
    /// When the source last updated the value (yyyy-mm-dd).
    public var updated: String?

    public init(
        dataPoints: Int? = nil, stdError: Double? = nil, min: Double? = nil, max: Double? = nil,
        median: Double? = nil, derivation: String? = nil, derivationDescription: String? = nil,
        derivationBasis: String? = nil, footnote: String? = nil, updated: String? = nil
    ) {
        self.dataPoints = dataPoints
        self.stdError = stdError
        self.min = min
        self.max = max
        self.median = median
        self.derivation = derivation
        self.derivationDescription = derivationDescription
        self.derivationBasis = derivationBasis
        self.footnote = footnote
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey {
        case min, max, median, derivation, footnote, updated
        case dataPoints = "data_points"
        case stdError = "std_error"
        case derivationDescription = "derivation_description"
        case derivationBasis = "derivation_basis"
    }
}

/// Every nutrient key a serving can have.
public struct NutrientList: Sendable, Hashable, Codable {
    /// Nutrients with a fixed key and unit; the core ones are always present in a serving.
    public var nutrients: [NutrientDefinition]
    /// Keys sources have given that don't have a fixed key yet ("usda_1018", "cnf_409", …).
    public var other: [OtherNutrient]

    public init(nutrients: [NutrientDefinition], other: [OtherNutrient]) {
        self.nutrients = nutrients
        self.other = other
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nutrients = try c.decodeIfPresent([NutrientDefinition].self, forKey: .nutrients) ?? []
        other = try c.decodeIfPresent([OtherNutrient].self, forKey: .other) ?? []
    }
}

/// A nutrient with a fixed key and unit.
public struct NutrientDefinition: Sendable, Hashable, Codable, Identifiable {
    public var key: String
    public var name: String
    public var unit: String
    /// energy, macro, sugar, fat, mineral, vitamin or other.
    public var group: String
    public var core: Bool

    public var id: String { key }

    public init(key: String, name: String, unit: String, group: String, core: Bool) {
        self.key = key
        self.name = name
        self.unit = unit
        self.group = group
        self.core = core
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        unit = try c.decode(String.self, forKey: .unit)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        core = try c.decodeIfPresent(Bool.self, forKey: .core) ?? false
    }
}

/// A nutrient key without a fixed one, as its source described it.
public struct OtherNutrient: Sendable, Hashable, Codable, Identifiable {
    public var key: String
    public var name: String
    public var unit: String
    public var source: String

    public var id: String { key }

    public init(key: String, name: String, unit: String, source: String) {
        self.key = key
        self.name = name
        self.unit = unit
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
    }
}

/// Every food image the API can give a food, for apps that bundle or prefetch them.
public struct ImageSet: Sendable, Hashable, Codable {
    /// Changes when the images are redrawn.
    public var version: Int
    /// yyyy-mm-dd.
    public var updated: String
    /// The key of the image used when nothing fits a food.
    public var fallback: String
    public var groups: [ImageGroup]
    public var images: [ImageEntry]

    public init(version: Int, updated: String, fallback: String, groups: [ImageGroup], images: [ImageEntry]) {
        self.version = version
        self.updated = updated
        self.fallback = fallback
        self.groups = groups
        self.images = images
    }

    /// The image with a key, or nil when the set has none.
    public func image(_ key: String) -> ImageEntry? { images.first { $0.key == key } }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? ""
        fallback = try c.decodeIfPresent(String.self, forKey: .fallback) ?? ""
        groups = try c.decodeIfPresent([ImageGroup].self, forKey: .groups) ?? []
        // An entry the SDK can't read is skipped rather than failing the whole set
        images = try c.decodeIfPresent([Lossy<ImageEntry>].self, forKey: .images)?.compactMap(\.value) ?? []
    }
}

/// A group of images, such as "Milk and dairy".
public struct ImageGroup: Sendable, Hashable, Codable, Identifiable {
    public var key: String
    public var label: String

    public var id: String { key }

    public init(key: String, label: String) {
        self.key = key
        self.label = label
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

/// One image of the set.
public struct ImageEntry: Sendable, Hashable, Codable, Identifiable {
    /// `group/slug`.
    public var key: String
    public var label: String
    public var tier: ImageTier
    /// The group's key.
    public var group: String
    /// The broader image it stands for when no closer one fits: its own key for a category image.
    public var category: String
    /// For a variant, the food image it is a form of; nil otherwise.
    public var parent: String?
    public var url: URL

    public var id: String { key }

    public init(
        key: String, label: String, tier: ImageTier, group: String, category: String, parent: String? = nil, url: URL
    ) {
        self.key = key
        self.label = label
        self.tier = tier
        self.group = group
        self.category = category
        self.parent = parent
        self.url = url
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        tier = try c.decodeIfPresent(ImageTier.self, forKey: .tier) ?? .unknown("")
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        url = try c.decode(URL.self, forKey: .url)
    }
}

// MARK: - Decoding helpers

private func decodeRawValue(_ decoder: any Decoder) throws -> String {
    try decoder.singleValueContainer().decode(String.self)
}

private func encodeRawValue(_ value: String, _ encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(value)
}

/// A string, or nothing for any other JSON value.
private struct TextOrNothing: Decodable {
    let text: String?
    init(from decoder: any Decoder) throws { text = try? decoder.singleValueContainer().decode(String.self) }
}

/// A value, or nothing when it doesn't decode.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
