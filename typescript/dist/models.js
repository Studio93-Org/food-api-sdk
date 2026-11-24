// Response models of the Food API (v2). Parsing is lenient: fields the SDK doesn't know are ignored, so newer API
// versions keep working with older SDKs.
import { entries, hasOwn, isObject, list, num, obj, str, stringMap, strOrNull } from './json.js';
/** Whether a food is a generic food (an apple, cooked rice) or a branded product. */
export const FoodType = {
    generic: 'generic',
    brand: 'brand',
    /** A type this version of the SDK doesn't know. */
    unknown: 'unknown',
};
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
};
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
};
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
};
function parseEnum(values, value, unknown) {
    for (const v of Object.values(values)) {
        if (v === value && v !== unknown)
            return v;
    }
    return unknown;
}
/** One food in the catalog, with its nutrition per serving. */
export class Food {
    id;
    name;
    brand;
    type;
    barcodes;
    servings;
    source;
    /** What the source says the food contains; null when unknown. */
    ingredients;
    /** The source's category; null when unknown. */
    category;
    /** Everything else the source gives about the food, as text. See `alternateNames`. */
    attributes;
    /** Nutrient values that aren't plain measurements, by nutrient key. They hold for every serving. */
    nutrientFlags;
    /** A picture of the food; null in answers from before the API had images. */
    image;
    constructor(fields) {
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
    static fromJson(json) {
        const j = obj(json);
        const source = obj(j['source']);
        const flags = {};
        for (const [key, value] of Object.entries(stringMap(j['nutrient_flags']))) {
            flags[key] = parseEnum(NutrientFlag, value, NutrientFlag.unknown);
        }
        const image = j['image'];
        return new Food({
            id: str(j['id']),
            name: str(j['name']),
            brand: strOrNull(j['brand']),
            type: parseEnum(FoodType, j['type'], FoodType.unknown),
            barcodes: list(j['barcodes']).filter((b) => typeof b === 'string'),
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
    get alternateNames() {
        return (this.attributes['alternate_names'] ?? '')
            .split(',')
            .map((name) => name.trim())
            .filter((name) => name !== '');
    }
    /** The flag of a nutrient value, or null when it has none. */
    flag(nutrient) {
        return hasOwn(this.nutrientFlags, nutrient) ? (this.nutrientFlags[nutrient] ?? null) : null;
    }
    /** The food as the API sends it. */
    toJSON() {
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
    key;
    url;
    /** How closely the image shows the food. */
    match;
    constructor(fields) {
        this.key = fields.key;
        this.url = fields.url;
        this.match = fields.match;
    }
    static fromJson(json) {
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
    get isFallback() {
        return this.match === ImageMatch.fallback;
    }
    toJSON() {
        return { key: this.key, url: this.url, match: this.match };
    }
}
function servingFromJson(json) {
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
function servingToJson(s) {
    const out = {
        description: s.description,
        measurement: s.measurement,
        metric_amount: s.metricAmount,
        metric_unit: s.metricUnit,
        units: s.units,
        nutrients: s.nutrients,
    };
    if (s.sourceId !== null)
        out['source_id'] = s.sourceId;
    if (s.generic)
        out['generic'] = true;
    return out;
}
/**
 * A serving's nutrient amounts by key, in the units `FoodApiClient.nutrients()` lists. The 17 core nutrients have
 * getters and are null when unknown; read any other key with `nutrients.get('magnesium')`.
 */
export class Nutrients {
    /** Every nutrient the serving has a key for; a null value means unknown. */
    values;
    constructor(values) {
        this.values = values;
    }
    static fromJson(json) {
        const values = {};
        for (const [key, value] of entries(json))
            values[key] = num(value);
        return new Nutrients(values);
    }
    /** The amount of a nutrient, or null when unknown. */
    get(key) {
        return hasOwn(this.values, key) ? (this.values[key] ?? null) : null;
    }
    /** kcal */
    get calories() {
        return this.get('calories');
    }
    /** g */
    get protein() {
        return this.get('protein');
    }
    /** g */
    get carbohydrate() {
        return this.get('carbohydrate');
    }
    /** g */
    get fat() {
        return this.get('fat');
    }
    /** g */
    get sugar() {
        return this.get('sugar');
    }
    /** g */
    get fiber() {
        return this.get('fiber');
    }
    /** g */
    get saturatedFat() {
        return this.get('saturated_fat');
    }
    /** g */
    get monounsaturatedFat() {
        return this.get('monounsaturated_fat');
    }
    /** g */
    get polyunsaturatedFat() {
        return this.get('polyunsaturated_fat');
    }
    /** mg */
    get cholesterol() {
        return this.get('cholesterol');
    }
    /** mg */
    get sodium() {
        return this.get('sodium');
    }
    /** mg */
    get potassium() {
        return this.get('potassium');
    }
    /** mg */
    get calcium() {
        return this.get('calcium');
    }
    /** mg */
    get iron() {
        return this.get('iron');
    }
    /** µg */
    get vitaminA() {
        return this.get('vitamin_a');
    }
    /** mg */
    get vitaminC() {
        return this.get('vitamin_c');
    }
    /** µg */
    get vitaminD() {
        return this.get('vitamin_d');
    }
    toJSON() {
        return { ...this.values };
    }
}
/** Every food image the API can give a food, for apps that bundle or prefetch them. */
export class ImageSet {
    /** Changes when the images are redrawn. */
    version;
    /** yyyy-mm-dd. */
    updated;
    /** The key of the image used when nothing fits a food. */
    fallback;
    groups;
    images;
    constructor(fields) {
        this.version = fields.version;
        this.updated = fields.updated;
        this.fallback = fields.fallback;
        this.groups = fields.groups;
        this.images = fields.images;
    }
    static fromJson(json) {
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
    image(key) {
        return this.images.find((image) => image.key === key) ?? null;
    }
}
/** @internal */
export function suggestionFromJson(json) {
    const j = obj(json);
    return { id: str(j['id']), name: str(j['name']), brand: strOrNull(j['brand']) };
}
/** @internal */
export function nutrientStatsFromJson(json) {
    const j = obj(json);
    const nutrients = {};
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
export function nutrientListFromJson(json) {
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
