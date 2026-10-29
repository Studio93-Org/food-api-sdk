/// Response models of the Food API (v2). Parsing is lenient: fields the SDK doesn't know are ignored, so newer API
/// versions keep working with older SDKs.
library;

/// Whether a food is a generic food (an apple, cooked rice) or a branded product.
enum FoodType {
  generic,
  brand,
  unknown;

  static FoodType parse(Object? value) => switch (value) {
    'generic' => FoodType.generic,
    'brand' => FoodType.brand,
    _ => FoodType.unknown,
  };
}

/// Marks a nutrient value that isn't a plain measurement. A value without a flag is as precise as its source says
/// nothing otherwise.
enum NutrientFlag {
  /// The label said "less than": the real amount is at most the value (show "< 1 g").
  upperBound,

  /// Rounded or estimated on the label, for example worked out from a % daily value.
  approximate,

  /// Set to 0 by the source without being measured.
  assumedZero,

  /// A flag this version of the SDK doesn't know.
  unknown;

  static NutrientFlag parse(Object? value) => switch (value) {
    'upper_bound' => NutrientFlag.upperBound,
    'approximate' => NutrientFlag.approximate,
    'assumed_zero' => NutrientFlag.assumedZero,
    _ => NutrientFlag.unknown,
  };
}

/// One food in the catalog, with its nutrition per serving.
class Food {
  Food({
    required this.id,
    required this.name,
    required this.type,
    required this.barcodes,
    required this.servings,
    required this.source,
    this.brand,
    this.ingredients,
    this.category,
    this.attributes = const {},
    this.nutrientFlags = const {},
  });

  factory Food.fromJson(Map<String, dynamic> json) => Food(
    id: json['id'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String?,
    type: FoodType.parse(json['type']),
    barcodes: _list(json['barcodes']).cast<String>(),
    servings: _list(json['servings']).map((s) => Serving.fromJson(s as Map<String, dynamic>)).toList(),
    source: FoodSource.fromJson(json['source'] as Map<String, dynamic>),
    ingredients: json['ingredients'] as String?,
    category: json['category'] as String?,
    attributes: _stringMap(json['attributes']),
    nutrientFlags: _stringMap(json['nutrient_flags']).map((k, v) => MapEntry(k, NutrientFlag.parse(v))),
  );

  final String id;
  final String name;
  final String? brand;
  final FoodType type;
  final List<String> barcodes;
  final List<Serving> servings;
  final FoodSource source;

  /// What the source says about the food; null when unknown.
  final String? ingredients;
  final String? category;

  /// Everything else the source gives about the food, as text. See [alternateNames].
  final Map<String, String> attributes;

  /// Nutrient values that aren't plain measurements, by nutrient key. They hold for every serving.
  final Map<String, NutrientFlag> nutrientFlags;

  /// Other names the source gives the food ("pop", "soda" for cola).
  List<String> get alternateNames =>
      (attributes['alternate_names'] ?? '').split(',').map((n) => n.trim()).where((n) => n.isNotEmpty).toList();

  /// The flag of a nutrient value, or null when it has none.
  NutrientFlag? flag(String nutrient) => nutrientFlags[nutrient];
}

/// Where a food's data comes from (USDA, CNF, FatSecret, OpenFoodFacts) and its ID there.
class FoodSource {
  const FoodSource({required this.provider, required this.id});

  factory FoodSource.fromJson(Map<String, dynamic> json) =>
      FoodSource(provider: json['provider'] as String, id: json['id'] as String);

  final String provider;
  final String id;
}

/// One way of measuring a food (a cup, 100 g, one bar), with the nutrients it contains.
class Serving {
  const Serving({
    required this.description,
    required this.measurement,
    required this.metricUnit,
    required this.nutrients,
    this.metricAmount,
    this.units,
    this.sourceId,
    this.generic = false,
  });

  factory Serving.fromJson(Map<String, dynamic> json) => Serving(
    description: json['description'] as String? ?? '',
    measurement: json['measurement'] as String? ?? '',
    metricAmount: _double(json['metric_amount']),
    metricUnit: json['metric_unit'] as String? ?? '',
    units: _double(json['units']),
    nutrients: Nutrients.fromJson(json['nutrients']),
    sourceId: json['source_id'] as String?,
    generic: json['generic'] == true,
  );

  final String description;
  final String measurement;
  final double? metricAmount;
  final String metricUnit;
  final double? units;
  final Nutrients nutrients;

  /// The source's own ID for the serving, when it has one.
  final String? sourceId;

  /// Whether the API worked this serving out from the source's ones (100 g, 1 oz, 1 fl oz, 1 cup, …). Generic
  /// servings come after the source's own.
  final bool generic;
}

/// A serving's nutrient amounts by key, in the units [FoodApiClient.nutrients] lists. The core nutrients have
/// getters and are null when unknown; read any other key with `nutrients['magnesium']`.
class Nutrients {
  const Nutrients(this.values);

  factory Nutrients.fromJson(Object? json) =>
      Nutrients({for (final e in (json as Map<String, dynamic>? ?? const {}).entries) e.key: _double(e.value)});

  /// Every nutrient the serving has a key for; a null value means unknown.
  final Map<String, double?> values;

  /// The amount of a nutrient, or null when unknown.
  double? operator [](String key) => values[key];

  double? get calories => values['calories']; // kcal
  double? get protein => values['protein']; // g
  double? get carbohydrate => values['carbohydrate']; // g
  double? get fat => values['fat']; // g
  double? get sugar => values['sugar']; // g
  double? get fiber => values['fiber']; // g
  double? get saturatedFat => values['saturated_fat']; // g
  double? get monounsaturatedFat => values['monounsaturated_fat']; // g
  double? get polyunsaturatedFat => values['polyunsaturated_fat']; // g
  double? get cholesterol => values['cholesterol']; // mg
  double? get sodium => values['sodium']; // mg
  double? get potassium => values['potassium']; // mg
  double? get calcium => values['calcium']; // mg
  double? get iron => values['iron']; // mg
  double? get vitaminA => values['vitamin_a']; // µg
  double? get vitaminC => values['vitamin_c']; // mg
  double? get vitaminD => values['vitamin_d']; // µg
}

/// One page of search results.
class SearchPage {
  const SearchPage({
    required this.foods,
    required this.query,
    required this.page,
    required this.limit,
    required this.total,
    required this.source,
    required this.cached,
  });

  final List<Food> foods;

  /// The query as searched: lowercase, single spaces.
  final String query;
  final int page;
  final int limit;
  final int total;

  /// "catalog", or "provider" when the catalog had no good match and the results came from an outside provider.
  final String source;

  /// Whether the API answered from its cache.
  final bool cached;
}

/// An autocomplete match: enough to show in a list. Look the food up with [FoodApiClient.food] when picked.
class Suggestion {
  const Suggestion({required this.id, required this.name, this.brand});

  factory Suggestion.fromJson(Map<String, dynamic> json) =>
      Suggestion(id: json['id'] as String, name: json['name'] as String, brand: json['brand'] as String?);

  final String id;
  final String name;
  final String? brand;
}

/// The suggestions for what has been typed so far.
class AutocompleteResult {
  const AutocompleteResult({
    required this.suggestions,
    required this.query,
    required this.limit,
    required this.total,
    required this.cached,
  });

  final List<Suggestion> suggestions;
  final String query;
  final int limit;

  /// How many foods match.
  final int total;
  final bool cached;
}

/// What a food's source says about each of its nutrient values, per 100 g.
class NutrientStats {
  const NutrientStats({required this.foodId, required this.per, required this.nutrients});

  factory NutrientStats.fromJson(Map<String, dynamic> json) => NutrientStats(
    foodId: json['id'] as String,
    per: json['per'] as String? ?? '100 g',
    nutrients: {
      for (final e in (json['nutrients'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: NutrientStat.fromJson(e.value as Map<String, dynamic>),
    },
  );

  final String foodId;
  final String per;
  final Map<String, NutrientStat> nutrients;
}

/// How one nutrient value was obtained. Amounts are per 100 g.
class NutrientStat {
  const NutrientStat({
    this.dataPoints,
    this.stdError,
    this.min,
    this.max,
    this.median,
    this.derivation,
    this.derivationDescription,
    this.derivationBasis,
    this.footnote,
    this.updated,
  });

  factory NutrientStat.fromJson(Map<String, dynamic> json) => NutrientStat(
    dataPoints: (json['data_points'] as num?)?.toInt(),
    stdError: _double(json['std_error']),
    min: _double(json['min']),
    max: _double(json['max']),
    median: _double(json['median']),
    derivation: json['derivation'] as String?,
    derivationDescription: json['derivation_description'] as String?,
    derivationBasis: json['derivation_basis'] as String?,
    footnote: json['footnote'] as String?,
    updated: json['updated'] as String?,
  );

  /// Samples the value comes from.
  final int? dataPoints;
  final double? stdError;
  final double? min;
  final double? max;
  final double? median;

  /// The source's code for how the value was obtained, and what it means.
  final String? derivation;
  final String? derivationDescription;
  final String? derivationBasis;
  final String? footnote;

  /// When the source last updated the value (yyyy-mm-dd).
  final String? updated;
}

/// Every nutrient key a serving can have.
class NutrientList {
  const NutrientList({required this.nutrients, required this.other});

  factory NutrientList.fromJson(Map<String, dynamic> json) => NutrientList(
    nutrients: _list(json['nutrients']).map((n) => NutrientDefinition.fromJson(n as Map<String, dynamic>)).toList(),
    other: _list(json['other']).map((n) => OtherNutrient.fromJson(n as Map<String, dynamic>)).toList(),
  );

  /// Nutrients with a fixed key and unit; the core ones are always present in a serving.
  final List<NutrientDefinition> nutrients;

  /// Keys sources have given that don't have a fixed key yet ("usda_1018", "cnf_409", …).
  final List<OtherNutrient> other;
}

/// A nutrient with a fixed key and unit.
class NutrientDefinition {
  const NutrientDefinition({
    required this.key,
    required this.name,
    required this.unit,
    required this.group,
    required this.core,
  });

  factory NutrientDefinition.fromJson(Map<String, dynamic> json) => NutrientDefinition(
    key: json['key'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String,
    group: json['group'] as String? ?? '',
    core: json['core'] as bool? ?? false,
  );

  final String key;
  final String name;
  final String unit;

  /// energy, macro, sugar, fat, mineral, vitamin or other.
  final String group;
  final bool core;
}

/// A nutrient key without a fixed one, as its source described it.
class OtherNutrient {
  const OtherNutrient({required this.key, required this.name, required this.unit, required this.source});

  factory OtherNutrient.fromJson(Map<String, dynamic> json) => OtherNutrient(
    key: json['key'] as String,
    name: json['name'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    source: json['source'] as String? ?? '',
  );

  final String key;
  final String name;
  final String unit;
  final String source;
}

double? _double(Object? v) => (v as num?)?.toDouble();

List<Object?> _list(Object? v) => (v as List<Object?>?) ?? const [];

Map<String, String> _stringMap(Object? v) => {
  for (final e in (v as Map<String, dynamic>? ?? const {}).entries)
    if (e.value is String) e.key: e.value as String,
};
