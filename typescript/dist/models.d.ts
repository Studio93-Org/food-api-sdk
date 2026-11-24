/** Whether a food is a generic food (an apple, cooked rice) or a branded product. */
export declare const FoodType: {
    readonly generic: "generic";
    readonly brand: "brand";
    /** A type this version of the SDK doesn't know. */
    readonly unknown: "unknown";
};
export type FoodType = (typeof FoodType)[keyof typeof FoodType];
/**
 * Marks a nutrient value that isn't a plain measurement. A value without a flag is as precise as its source says
 * nothing otherwise.
 */
export declare const NutrientFlag: {
    /** The label said "less than": the real amount is at most the value (show "< 1 g"). */
    readonly upperBound: "upper_bound";
    /** Rounded or estimated on the label, for example worked out from a % daily value. */
    readonly approximate: "approximate";
    /** Set to 0 by the source without being measured. */
    readonly assumedZero: "assumed_zero";
    /** A flag this version of the SDK doesn't know. */
    readonly unknown: "unknown";
};
export type NutrientFlag = (typeof NutrientFlag)[keyof typeof NutrientFlag];
/** How closely a food's image shows it. */
export declare const ImageMatch: {
    /** This food in its form or flavour (whole milk, not just milk). */
    readonly variant: "variant";
    /** This food. */
    readonly food: "food";
    /** The kind of food it is, for example cheese for a gouda. */
    readonly category: "category";
    /** Nothing fitted, so a generic plate, drink or meal; apps may prefer to show none. */
    readonly fallback: "fallback";
    /** A value this version of the SDK doesn't know: treat it like `category`. */
    readonly unknown: "unknown";
};
export type ImageMatch = (typeof ImageMatch)[keyof typeof ImageMatch];
/** How specific an image of the set is. */
export declare const ImageTier: {
    /** A kind of food (cheese). */
    readonly category: "category";
    /** One food (cheddar). */
    readonly food: "food";
    /** A form of a food (whole milk). */
    readonly variant: "variant";
    /** A tier this version of the SDK doesn't know. */
    readonly unknown: "unknown";
};
export type ImageTier = (typeof ImageTier)[keyof typeof ImageTier];
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
export declare class Food {
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
    constructor(fields: FoodFields);
    /**
     * Reads a food as the API sends it. `JSON.stringify(food)` writes that form again, so a food you stored reads
     * back with `Food.fromJson(JSON.parse(text))`.
     */
    static fromJson(json: unknown): Food;
    /** Other names the source gives the food ("pop", "soda" for cola). */
    get alternateNames(): string[];
    /** The flag of a nutrient value, or null when it has none. */
    flag(nutrient: string): NutrientFlag | null;
    /** The food as the API sends it. */
    toJSON(): Record<string, unknown>;
}
/**
 * A picture of a food from the API's image set: a 256 px JPEG. The URL is public (it needs no API key) and never
 * changes for a key, so it can be cached for good.
 */
export declare class FoodImage {
    /** `group/slug`, as in `FoodApiClient.images()` ("dairy/cheddar"). */
    readonly key: string;
    readonly url: string;
    /** How closely the image shows the food. */
    readonly match: ImageMatch;
    constructor(fields: {
        key: string;
        url: string;
        match: ImageMatch;
    });
    static fromJson(json: unknown): FoodImage;
    /**
     * Whether this is the generic picture used when nothing fitted the food (a plate, a drink); apps may prefer to
     * show none.
     */
    get isFallback(): boolean;
    toJSON(): Record<string, unknown>;
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
/**
 * A serving's nutrient amounts by key, in the units `FoodApiClient.nutrients()` lists. The 17 core nutrients have
 * getters and are null when unknown; read any other key with `nutrients.get('magnesium')`.
 */
export declare class Nutrients {
    /** Every nutrient the serving has a key for; a null value means unknown. */
    readonly values: Readonly<Record<string, number | null>>;
    constructor(values: Record<string, number | null>);
    static fromJson(json: unknown): Nutrients;
    /** The amount of a nutrient, or null when unknown. */
    get(key: string): number | null;
    /** kcal */
    get calories(): number | null;
    /** g */
    get protein(): number | null;
    /** g */
    get carbohydrate(): number | null;
    /** g */
    get fat(): number | null;
    /** g */
    get sugar(): number | null;
    /** g */
    get fiber(): number | null;
    /** g */
    get saturatedFat(): number | null;
    /** g */
    get monounsaturatedFat(): number | null;
    /** g */
    get polyunsaturatedFat(): number | null;
    /** mg */
    get cholesterol(): number | null;
    /** mg */
    get sodium(): number | null;
    /** mg */
    get potassium(): number | null;
    /** mg */
    get calcium(): number | null;
    /** mg */
    get iron(): number | null;
    /** µg */
    get vitaminA(): number | null;
    /** mg */
    get vitaminC(): number | null;
    /** µg */
    get vitaminD(): number | null;
    toJSON(): Record<string, number | null>;
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
export declare class ImageSet {
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
    });
    static fromJson(json: unknown): ImageSet;
    /** The image with a key, or null when the set has none. */
    image(key: string): ImageEntry | null;
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
