// Response models of the Food API (v2). Parsing is lenient: fields the SDK doesn't know are ignored, so newer API
// versions keep working with older SDKs.

import { entries, hasOwn, isObject, list, num, obj, str, stringMap, strOrNull } from './json.js';

/** Whether a food is a generic food (an apple, cooked rice) or a branded product. */
export const FoodType = {
  generic: 'generic',
  brand: 'brand',
  /** A type this version of the SDK doesn't know. */
  unknown: 'unknown',
} as const;
export type FoodType = (typeof FoodType)[keyof typeof FoodType];

/**
 * Marks a nutrient value that isn't a plain measurement. A value without a flag is as precise as its source says
 * nothing otherwise.
 */
export const NutrientFlag = {
  /** The label said "less than": the real amount is at most the value (show "< 1 g"). */
  upperBound: 'upper_bound',
  /** Rounded or estimated on the label, for example worked out from a % daily value. */
  approximate: 'approximate',
  /** Set to 0 by the source without being measured. */
  assumedZero: 'assumed_zero',
  /** A flag this version of the SDK doesn't know. */
  unknown: 'unknown',
} as const;
export type NutrientFlag = (typeof NutrientFlag)[keyof typeof NutrientFlag];

/** How closely a food's image shows it. */
export const ImageMatch = {
  /** This food in its form or flavour (whole milk, not just milk). */
  variant: 'variant',
  /** This food. */
  food: 'food',
  /** The kind of food it is, for example cheese for a gouda. */
  category: 'category',
  /** Nothing fitted, so a generic plate, drink or meal; apps may prefer to show none. */
  fallback: 'fallback',
  /** A value this version of the SDK doesn't know: treat it like `category`. */
  unknown: 'unknown',
} as const;
export type ImageMatch = (typeof ImageMatch)[keyof typeof ImageMatch];

/** How specific an image of the set is. */
export const ImageTier = {
  /** A kind of food (cheese). */
  category: 'category',
  /** One food (cheddar). */
  food: 'food',
  /** A form of a food (whole milk). */
  variant: 'variant',
  /** A tier this version of the SDK doesn't know. */
  unknown: 'unknown',
} as const;
export type ImageTier = (typeof ImageTier)[keyof typeof ImageTier];

function parseEnum<T extends string>(values: Readonly<Record<string, T>>, value: unknown, unknown: T): T {
  for (const v of Object.values(values)) {
    if (v === value && v !== unknown) return v;
  }
  return unknown;
}

/** Where a food's data comes from (USDA, CNF, CoFID, FatSecret, OpenFoodFacts) and its ID there. */
export interface FoodSource {
  readonly provider: string;
  readonly id: string;
}

/** The fields of a Food, for building one yourself (in tests, for example). */
export interface FoodFields {
  id: string;
  name: string;
  brand?: string | null;
  type: FoodType;
  barcodes?: string[];
  servings: Serving[];
  source: FoodSource;
  ingredients?: string | null;
  category?: string | null;
  attributes?: Record<string, string>;
  nutrientFlags?: Record<string, NutrientFlag>;
  image?: FoodImage | null;
}

/** One food in the catalog, with its nutrition per serving. */
export class Food {
  readonly id: string;
  readonly name: string;
  readonly brand: string | null;
  readonly type: FoodType;
  readonly barcodes: string[];
  readonly servings: Serving[];
  readonly source: FoodSource;
  /** What the source says the food contains; null when unknown. */
  readonly ingredients: string | null;
  /** The source's category; null when unknown. */
  readonly category: string | null;
  /** Everything else the source gives about the food, as text. See `alternateNames`. */
  readonly attributes: Record<string, string>;
  /** Nutrient values that aren't plain measurements, by nutrient key. They hold for every serving. */
  readonly nutrientFlags: Record<string, NutrientFlag>;
  /** A picture of the food; null in answers from before the API had images. */
  readonly image: FoodImage | null;

  constructor(fields: FoodFields) {
    this.id = fields.id;
    this.name = fields.name;
    this.brand = fields.brand ?? null;
    this.type = fields.type;
    this.barcodes = fields.barcodes ?? [];
    this.servings = fields.servings;
    this.source = fields.source;
    this.ingredients = fields.ingredients ?? null;
    this.category = fields.category ?? null;
    this.attributes = fields.attributes ?? {};
    this.nutrientFlags = fields.nutrientFlags ?? {};
    this.image = fields.image ?? null;
  }

  /**
   * Reads a food as the API sends it. `JSON.stringify(food)` writes that form again, so a food you stored reads
   * back with `Food.fromJson(JSON.parse(text))`.
   */
  static fromJson(json: unknown): Food {
    const j = obj(json);
    const source = obj(j['source']);
    const flags: Record<string, NutrientFlag> = {};
    for (const [key, value] of Object.entries(stringMap(j['nutrient_flags']))) {
      flags[key] = parseEnum(NutrientFlag, value, NutrientFlag.unknown);
    }
    const image = j['image'];
    return new Food({
      id: str(j['id']),
      name: str(j['name']),
      brand: strOrNull(j['brand']),
      type: parseEnum(FoodType, j['type'], FoodType.unknown),
      barcodes: list(j['barcodes']).filter((b): b is string => typeof b === 'string'),
      servings: list(j['servings']).map(servingFromJson),
      source: { provider: str(source['provider']), id: str(source['id']) },
      ingredients: strOrNull(j['ingredients']),
      category: strOrNull(j['category']),
      attributes: stringMap(j['attributes']),
      nutrientFlags: flags,
      image: isObject(image) ? FoodImage.fromJson(image) : null,
    });
  }

  /** Other names the source gives the food ("pop", "soda" for cola). */
  get alternateNames(): string[] {
    return (this.attributes['alternate_names'] ?? '')
      .split(',')
      .map((name) => name.trim())
      .filter((name) => name !== '');
  }

  /** The flag of a nutrient value, or null when it has none. */
  flag(nutrient: string): NutrientFlag | null {
    return hasOwn(this.nutrientFlags, nutrient) ? (this.nutrientFlags[nutrient] ?? null) : null;
  }

  /** The food as the API sends it. */
  toJSON(): Record<string, unknown> {
    return {
      id: this.id,
      name: this.name,
      brand: this.brand,
      type: this.type,
      barcodes: this.barcodes,
      servings: this.servings.map(servingToJson),
      source: this.source,
      ingredients: this.ingredients,
      category: this.category,
      attributes: this.attributes,
      nutrient_flags: this.nutrientFlags,
      image: this.image,
    };
  }
}

/**
 * A picture of a food from the API's image set: a 256 px JPEG. The URL is public (it needs no API key) and never
 * changes for a key, so it can be cached for good.
 */
export class FoodImage {
  /** `group/slug`, as in `FoodApiClient.images()` ("dairy/cheddar"). */
  readonly key: string;
  readonly url: string;
  /** How closely the image shows the food. */
  readonly match: ImageMatch;

  constructor(fields: { key: string; url: string; match: ImageMatch }) {
    this.key = fields.key;
    this.url = fields.url;
    this.match = fields.match;
  }

  static fromJson(json: unknown): FoodImage {
    const j = obj(json);
    return new FoodImage({
      key: str(j['key']),
      url: str(j['url']),
      match: parseEnum(ImageMatch, j['match'], ImageMatch.unknown),
    });
  }

  /**
   * Whether this is the generic picture used when nothing fitted the food (a plate, a drink); apps may prefer to
   * show none.
   */
  get isFallback(): boolean {
    return this.match === ImageMatch.fallback;
  }

  toJSON(): Record<string, unknown> {
    return { key: this.key, url: this.url, match: this.match };
  }
}

/** One way of measuring a food (a cup, 100 g, one bar), with the nutrients it contains. */
export interface Serving {
  readonly description: string;
  readonly measurement: string;
  readonly metricAmount: number | null;
  readonly metricUnit: string;
  readonly units: number | null;
  readonly nutrients: Nutrients;
  /** The source's own ID for the serving, when it has one. */
  readonly sourceId: string | null;
  /**
   * Whether the API worked this serving out from the source's ones (100 g, 1 oz, 1 fl oz, 1 cup, …). Generic
   * servings come after the source's own.
   */
  readonly generic: boolean;
}

function servingFromJson(json: unknown): Serving {
  const j = obj(json);
  return {
    description: str(j['description']),
    measurement: str(j['measurement']),
    metricAmount: num(j['metric_amount']),
    metricUnit: str(j['metric_unit']),
    units: num(j['units']),
    nutrients: Nutrients.fromJson(j['nutrients']),
    sourceId: strOrNull(j['source_id']),
    generic: j['generic'] === true,
  };
}

function servingToJson(s: Serving): Record<string, unknown> {
  const out: Record<string, unknown> = {
    description: s.description,
    measurement: s.measurement,
    metric_amount: s.metricAmount,
    metric_unit: s.metricUnit,
    units: s.units,
    nutrients: s.nutrients,
  };
  if (s.sourceId !== null) out['source_id'] = s.sourceId;
  if (s.generic) out['generic'] = true;
  return out;
}

/**
 * A serving's nutrient amounts by key, in the units `FoodApiClient.nutrients()` lists. The 17 core nutrients have
 * getters and are null when unknown; read any other key with `nutrients.get('magnesium')`.
 */
export class Nutrients {
  /** Every nutrient the serving has a key for; a null value means unknown. */
  readonly values: Readonly<Record<string, number | null>>;

  constructor(values: Record<string, number | null>) {
    this.values = values;
  }

  static fromJson(json: unknown): Nutrients {
    const values: Record<string, number | null> = {};
    for (const [key, value] of entries(json)) values[key] = num(value);
    return new Nutrients(values);
  }

  /** The amount of a nutrient, or null when unknown. */
  get(key: string): number | null {
    return hasOwn(this.values, key) ? (this.values[key] ?? null) : null;
  }

  /** kcal */
  get calories(): number | null {
    return this.get('calories');
  }
  /** g */
  get protein(): number | null {
    return this.get('protein');
  }
  /** g */
  get carbohydrate(): number | null {
    return this.get('carbohydrate');
  }
  /** g */
  get fat(): number | null {
    return this.get('fat');
  }
  /** g */
  get sugar(): number | null {
    return this.get('sugar');
  }
  /** g */
  get fiber(): number | null {
    return this.get('fiber');
  }
  /** g */
  get saturatedFat(): number | null {
    return this.get('saturated_fat');
  }
  /** g */
  get monounsaturatedFat(): number | null {
    return this.get('monounsaturated_fat');
  }
  /** g */
  get polyunsaturatedFat(): number | null {
    return this.get('polyunsaturated_fat');
  }
  /** mg */
  get cholesterol(): number | null {
    return this.get('cholesterol');
  }
  /** mg */
  get sodium(): number | null {
    return this.get('sodium');
  }
  /** mg */
  get potassium(): number | null {
    return this.get('potassium');
  }
  /** mg */
  get calcium(): number | null {
    return this.get('calcium');
  }
  /** mg */
  get iron(): number | null {
    return this.get('iron');
  }
  /** µg */
  get vitaminA(): number | null {
    return this.get('vitamin_a');
  }
  /** mg */
  get vitaminC(): number | null {
    return this.get('vitamin_c');
  }
  /** µg */
  get vitaminD(): number | null {
    return this.get('vitamin_d');
  }

  toJSON(): Record<string, number | null> {
    return { ...this.values };
  }
}

/** One page of search results. */
export interface SearchPage {
  readonly foods: Food[];
  /** The query as searched: lowercase, single spaces. */
  readonly query: string;
  readonly page: number;
  readonly limit: number;
  readonly total: number;
  /** "catalog", or "provider" when the catalog had no good match and the results came from an outside provider. */
  readonly source: string;
  /**
   * With regional ranking, the country whose foods ranked first among equally good matches (an ISO code such as
   * "CA"); null when none did.
   */
  readonly region: string | null;
  /** The brand the query names, whose foods ranked first ("Coca-Cola" for "coke"); null when it names none. */
  readonly brand: string | null;
  /** Whether the API answered from its cache. */
  readonly cached: boolean;
}

/** An autocomplete match: enough to show in a list. Look the food up with `FoodApiClient.food()` when picked. */
export interface Suggestion {
  readonly id: string;
  readonly name: string;
  readonly brand: string | null;
}

/** The suggestions for what has been typed so far. */
export interface AutocompleteResult {
  readonly suggestions: Suggestion[];
  readonly query: string;
  readonly limit: number;
  /** How many foods match. */
  readonly total: number;
  readonly cached: boolean;
}

/** What a food's source says about each of its nutrient values, per 100 g. */
export interface NutrientStats {
  readonly foodId: string;
  readonly per: string;
  readonly nutrients: Record<string, NutrientStat>;
}

/** How one nutrient value was obtained. Amounts are per 100 g. */
export interface NutrientStat {
  /** Samples the value comes from. */
  readonly dataPoints: number | null;
  readonly stdError: number | null;
  readonly min: number | null;
  readonly max: number | null;
  readonly median: number | null;
  /** The source's code for how the value was obtained. */
  readonly derivation: string | null;
  /** What the derivation code means. */
  readonly derivationDescription: string | null;
  readonly derivationBasis: string | null;
  readonly footnote: string | null;
  /** When the source last updated the value (yyyy-mm-dd). */
  readonly updated: string | null;
}

/** Every nutrient key a serving can have. */
export interface NutrientList {
  /** Nutrients with a fixed key and unit; the core ones are always present in a serving. */
  readonly nutrients: NutrientDefinition[];
  /** Keys sources have given that don't have a fixed key yet ("usda_1018", "cnf_409", …). */
  readonly other: OtherNutrient[];
}

/** A nutrient with a fixed key and unit. */
export interface NutrientDefinition {
  readonly key: string;
  readonly name: string;
  readonly unit: string;
  /** energy, macro, sugar, fat, mineral, vitamin or other. */
  readonly group: string;
  readonly core: boolean;
}

/** A nutrient key without a fixed one, as its source described it. */
export interface OtherNutrient {
  readonly key: string;
  readonly name: string;
  readonly unit: string;
  readonly source: string;
}

/** Every food image the API can give a food, for apps that bundle or prefetch them. */
export class ImageSet {
  /** Changes when the images are redrawn. */
  readonly version: number;
  /** yyyy-mm-dd. */
  readonly updated: string;
  /** The key of the image used when nothing fits a food. */
  readonly fallback: string;
  readonly groups: ImageGroup[];
  readonly images: ImageEntry[];

  constructor(fields: {
    version: number;
    updated: string;
    fallback: string;
    groups: ImageGroup[];
    images: ImageEntry[];
  }) {
    this.version = fields.version;
    this.updated = fields.updated;
    this.fallback = fields.fallback;
    this.groups = fields.groups;
    this.images = fields.images;
  }

  static fromJson(json: unknown): ImageSet {
    const j = obj(json);
    return new ImageSet({
      version: num(j['version']) ?? 0,
      updated: str(j['updated']),
      fallback: str(j['fallback']),
      groups: list(j['groups']).map((g) => {
        const group = obj(g);
        return { key: str(group['key']), label: str(group['label']) };
      }),
      images: list(j['images']).map((i) => {
        const image = obj(i);
        return {
          key: str(image['key']),
          label: str(image['label']),
          tier: parseEnum(ImageTier, image['tier'], ImageTier.unknown),
          group: str(image['group']),
          category: str(image['category']),
          parent: strOrNull(image['parent']),
          url: str(image['url']),
        };
      }),
    });
  }

  /** The image with a key, or null when the set has none. */
  image(key: string): ImageEntry | null {
    return this.images.find((image) => image.key === key) ?? null;
  }
}

/** A group of images, such as "Milk and dairy". */
export interface ImageGroup {
  readonly key: string;
  readonly label: string;
}

/** One image of the set. */
export interface ImageEntry {
  /** `group/slug`. */
  readonly key: string;
  readonly label: string;
  readonly tier: ImageTier;
  /** The group's key. */
  readonly group: string;
  /** The broader image it stands for when no closer one fits: its own key for a category image. */
  readonly category: string;
  /** For a variant, the food image it is a form of; null otherwise. */
  readonly parent: string | null;
  readonly url: string;
}

/** @internal */
export function suggestionFromJson(json: unknown): Suggestion {
  const j = obj(json);
  return { id: str(j['id']), name: str(j['name']), brand: strOrNull(j['brand']) };
}

/** @internal */
export function nutrientStatsFromJson(json: unknown): NutrientStats {
  const j = obj(json);
  const nutrients: Record<string, NutrientStat> = {};
  for (const [key, value] of entries(j['nutrients'])) {
    const s = obj(value);
    const dataPoints = num(s['data_points']);
    nutrients[key] = {
      dataPoints: dataPoints === null ? null : Math.trunc(dataPoints),
      stdError: num(s['std_error']),
      min: num(s['min']),
      max: num(s['max']),
      median: num(s['median']),
      derivation: strOrNull(s['derivation']),
      derivationDescription: strOrNull(s['derivation_description']),
      derivationBasis: strOrNull(s['derivation_basis']),
      footnote: strOrNull(s['footnote']),
      updated: strOrNull(s['updated']),
    };
  }
  return { foodId: str(j['id']), per: typeof j['per'] === 'string' ? j['per'] : '100 g', nutrients };
}

/** @internal */
export function nutrientListFromJson(json: unknown): NutrientList {
  const j = obj(json);
  return {
    nutrients: list(j['nutrients']).map((n) => {
      const d = obj(n);
      return {
        key: str(d['key']),
        name: str(d['name']),
        unit: str(d['unit']),
        group: str(d['group']),
        core: d['core'] === true,
      };
    }),
    other: list(j['other']).map((n) => {
      const d = obj(n);
      return { key: str(d['key']), name: str(d['name']), unit: str(d['unit']), source: str(d['source']) };
    }),
  };
}
