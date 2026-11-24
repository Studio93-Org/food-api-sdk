// Response models of the Food API (v2). Parsing is lenient: JSON keys the SDK doesn't know are ignored and enum values
// newer than the SDK parse as UNKNOWN, so newer API versions keep working with older SDKs.

package io.studio93.foodapi

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** Whether a food is a generic food (an apple, cooked rice) or a branded product. */
@Serializable(with = FoodTypeSerializer::class)
public enum class FoodType(public val value: String) {
    GENERIC("generic"),
    BRAND("brand"),

    /** A type this version of the SDK doesn't know. */
    UNKNOWN("unknown"),
}

/**
 * Marks a nutrient value that isn't a plain measurement. A value without a flag is as precise as its source says
 * nothing otherwise.
 */
@Serializable(with = NutrientFlagSerializer::class)
public enum class NutrientFlag(public val value: String) {
    /** The label said "less than": the real amount is at most the value (show "< 1 g"). */
    UPPER_BOUND("upper_bound"),

    /** Rounded or estimated on the label, for example worked out from a % daily value. */
    APPROXIMATE("approximate"),

    /** Set to 0 by the source without being measured. */
    ASSUMED_ZERO("assumed_zero"),

    /** A flag this version of the SDK doesn't know. */
    UNKNOWN("unknown"),
}

/** How closely a food's image shows it. */
@Serializable(with = ImageMatchSerializer::class)
public enum class ImageMatch(public val value: String) {
    /** This food in its form or flavour (whole milk, not just milk). */
    VARIANT("variant"),

    /** This food. */
    FOOD("food"),

    /** The kind of food it is, for example cheese for a gouda. */
    CATEGORY("category"),

    /** Nothing fitted, so a generic plate, drink or meal; apps may prefer to show none. */
    FALLBACK("fallback"),

    /** A value this version of the SDK doesn't know: treat it like [CATEGORY]. */
    UNKNOWN("unknown"),
}

/** How specific an image of the set is. */
@Serializable(with = ImageTierSerializer::class)
public enum class ImageTier(public val value: String) {
    /** A kind of food (cheese). */
    CATEGORY("category"),

    /** One food (cheddar). */
    FOOD("food"),

    /** A form of a food (whole milk). */
    VARIANT("variant"),

    /** A tier this version of the SDK doesn't know. */
    UNKNOWN("unknown"),
}

/** One food in the catalog, with its nutrition per serving. */
@Serializable
public data class Food(
    val id: String,
    val name: String,
    val brand: String? = null,
    val type: FoodType = FoodType.UNKNOWN,
    val barcodes: List<String> = emptyList(),
    val servings: List<Serving> = emptyList(),
    val source: FoodSource = FoodSource("", ""),
    /** What the source says the food contains; null when unknown. */
    val ingredients: String? = null,
    /** The source's category for the food; null when unknown. */
    val category: String? = null,
    /** Everything else the source gives about the food, as text. See [alternateNames]. */
    val attributes: Map<String, String> = emptyMap(),
    /** Nutrient values that aren't plain measurements, by nutrient key. They hold for every serving. */
    @SerialName("nutrient_flags") val nutrientFlags: Map<String, NutrientFlag> = emptyMap(),
    /** A picture of the food; null in answers from before the API had images. */
    val image: FoodImage? = null,
) {
    /** Other names the source gives the food ("pop", "soda" for cola). */
    val alternateNames: List<String>
        get() = (attributes["alternate_names"] ?: "").split(',').map { it.trim() }.filter { it.isNotEmpty() }

    /** The flag of a nutrient value, or null when it has none. */
    public fun flag(nutrient: String): NutrientFlag? = nutrientFlags[nutrient]
}

/**
 * A picture of a food from the API's image set: a 256 px JPEG. The URL is public (it needs no API key) and never
 * changes for a key, so it can be cached for good.
 */
@Serializable
public data class FoodImage(
    /** `group/slug`, as in [FoodApiClient.images] ("dairy/cheddar"). */
    val key: String = "",
    val url: String = "",
    /** How closely the image shows the food. */
    val match: ImageMatch = ImageMatch.UNKNOWN,
) {
    /**
     * Whether this is the generic picture used when nothing fitted the food (a plate, a drink); apps may prefer to
     * show none.
     */
    val isFallback: Boolean get() = match == ImageMatch.FALLBACK
}

/** Where a food's data comes from (USDA, CNF, FatSecret, OpenFoodFacts) and its ID there. */
@Serializable
public data class FoodSource(val provider: String = "", val id: String = "")

/** One way of measuring a food (a cup, 100 g, one bar), with the nutrients it contains. */
@Serializable
public data class Serving(
    val description: String = "",
    val measurement: String = "",
    @SerialName("metric_amount") val metricAmount: Double? = null,
    @SerialName("metric_unit") val metricUnit: String = "",
    val units: Double? = null,
    val nutrients: Nutrients = Nutrients(emptyMap()),
    /** The source's own ID for the serving, when it has one. */
    @SerialName("source_id") val sourceId: String? = null,
    /**
     * Whether the API worked this serving out from the source's ones (100 g, 1 oz, 1 fl oz, 1 cup, …). Generic
     * servings come after the source's own.
     */
    val generic: Boolean = false,
)

/**
 * A serving's nutrient amounts by key, in the units [FoodApiClient.nutrients] lists. The core nutrients have
 * properties and are null when unknown; read any other key with `nutrients["magnesium"]`.
 */
@Serializable(with = NutrientsSerializer::class)
public class Nutrients(
    /** Every nutrient the serving has a key for; a null value means unknown. */
    public val values: Map<String, Double?>,
) {
    /** The amount of a nutrient, or null when unknown. */
    public operator fun get(key: String): Double? = values[key]

    /** kcal */
    public val calories: Double? get() = values[CALORIES]

    /** g */
    public val protein: Double? get() = values[PROTEIN]

    /** g */
    public val carbohydrate: Double? get() = values[CARBOHYDRATE]

    /** g */
    public val fat: Double? get() = values[FAT]

    /** g */
    public val sugar: Double? get() = values[SUGAR]

    /** g */
    public val fiber: Double? get() = values[FIBER]

    /** g */
    public val saturatedFat: Double? get() = values[SATURATED_FAT]

    /** g */
    public val monounsaturatedFat: Double? get() = values[MONOUNSATURATED_FAT]

    /** g */
    public val polyunsaturatedFat: Double? get() = values[POLYUNSATURATED_FAT]

    /** mg */
    public val cholesterol: Double? get() = values[CHOLESTEROL]

    /** mg */
    public val sodium: Double? get() = values[SODIUM]

    /** mg */
    public val potassium: Double? get() = values[POTASSIUM]

    /** mg */
    public val calcium: Double? get() = values[CALCIUM]

    /** mg */
    public val iron: Double? get() = values[IRON]

    /** µg */
    public val vitaminA: Double? get() = values[VITAMIN_A]

    /** mg */
    public val vitaminC: Double? get() = values[VITAMIN_C]

    /** µg */
    public val vitaminD: Double? get() = values[VITAMIN_D]

    override fun equals(other: Any?): Boolean = other is Nutrients && other.values == values

    override fun hashCode(): Int = values.hashCode()

    override fun toString(): String = "Nutrients($values)"

    /** The core nutrient keys: every serving has them, null when unknown. */
    public companion object {
        public const val CALORIES: String = "calories"
        public const val PROTEIN: String = "protein"
        public const val CARBOHYDRATE: String = "carbohydrate"
        public const val FAT: String = "fat"
        public const val SUGAR: String = "sugar"
        public const val FIBER: String = "fiber"
        public const val SATURATED_FAT: String = "saturated_fat"
        public const val MONOUNSATURATED_FAT: String = "monounsaturated_fat"
        public const val POLYUNSATURATED_FAT: String = "polyunsaturated_fat"
        public const val CHOLESTEROL: String = "cholesterol"
        public const val SODIUM: String = "sodium"
        public const val POTASSIUM: String = "potassium"
        public const val CALCIUM: String = "calcium"
        public const val IRON: String = "iron"
        public const val VITAMIN_A: String = "vitamin_a"
        public const val VITAMIN_C: String = "vitamin_c"
        public const val VITAMIN_D: String = "vitamin_d"
    }
}

/** One page of search results. */
@Serializable
public data class SearchPage(
    val foods: List<Food>,
    /** The query as searched: lowercase, single spaces. */
    val query: String,
    val page: Int,
    val limit: Int,
    val total: Long,
    /** "catalog", or "provider" when the catalog had no good match and the results came from an outside provider. */
    val source: String,
    /**
     * With regional ranking, the country whose foods ranked first among equally good matches (an ISO code such as
     * "CA"); null when none did. Apps on the user's device send nothing: the API finds the country from the address.
     */
    val region: String? = null,
    /** The brand the query names, whose foods ranked first ("Coca-Cola" for "coke"); null when it names none. */
    val brand: String? = null,
    /** Whether the API answered from its cache. */
    val cached: Boolean = false,
)

/** An autocomplete match: enough to show in a list. Look the food up with [FoodApiClient.food] when picked. */
@Serializable
public data class Suggestion(val id: String, val name: String, val brand: String? = null)

/** The suggestions for what has been typed so far. */
@Serializable
public data class AutocompleteResult(
    val suggestions: List<Suggestion>,
    val query: String,
    val limit: Int,
    /** How many foods match. */
    val total: Long,
    val cached: Boolean = false,
)

/** What a food's source says about each of its nutrient values, per 100 g. */
@Serializable
public data class NutrientStats(
    @SerialName("id") val foodId: String,
    val per: String = "100 g",
    val nutrients: Map<String, NutrientStat> = emptyMap(),
)

/** How one nutrient value was obtained. Amounts are per 100 g. */
@Serializable
public data class NutrientStat(
    /** Samples the value comes from. */
    @SerialName("data_points") val dataPoints: Int? = null,
    @SerialName("std_error") val stdError: Double? = null,
    val min: Double? = null,
    val max: Double? = null,
    val median: Double? = null,
    /** The source's code for how the value was obtained. */
    val derivation: String? = null,
    /** What [derivation] means. */
    @SerialName("derivation_description") val derivationDescription: String? = null,
    @SerialName("derivation_basis") val derivationBasis: String? = null,
    val footnote: String? = null,
    /** When the source last updated the value (yyyy-mm-dd). */
    val updated: String? = null,
)

/** Every nutrient key a serving can have. */
@Serializable
public data class NutrientList(
    /** Nutrients with a fixed key and unit; the core ones are always present in a serving. */
    val nutrients: List<NutrientDefinition> = emptyList(),
    /** Keys sources have given that don't have a fixed key yet ("usda_1018", "cnf_409", …). */
    val other: List<OtherNutrient> = emptyList(),
)

/** A nutrient with a fixed key and unit. */
@Serializable
public data class NutrientDefinition(
    val key: String,
    val name: String = "",
    val unit: String = "",
    /** energy, macro, sugar, fat, mineral, vitamin or other. */
    val group: String = "",
    val core: Boolean = false,
)

/** A nutrient key without a fixed one, as its source described it. */
@Serializable
public data class OtherNutrient(
    val key: String,
    val name: String = "",
    val unit: String = "",
    val source: String = "",
)

/** Every food image the API can give a food, for apps that bundle or prefetch them. */
@Serializable
public data class ImageSet(
    /** Changes when the images are redrawn. */
    val version: Int = 0,
    /** yyyy-mm-dd. */
    val updated: String = "",
    /** The key of the image used when nothing fits a food. */
    val fallback: String = "",
    val groups: List<ImageGroup> = emptyList(),
    val images: List<ImageEntry> = emptyList(),
) {
    /** The image with [key], or null when the set has none. */
    public fun image(key: String): ImageEntry? = images.firstOrNull { it.key == key }
}

/** A group of images, such as "Milk and dairy". */
@Serializable
public data class ImageGroup(val key: String, val label: String = "")

/** One image of the set. */
@Serializable
public data class ImageEntry(
    /** `group/slug`. */
    val key: String,
    val label: String = "",
    val tier: ImageTier = ImageTier.UNKNOWN,
    /** The group's key. */
    val group: String = "",
    /** The broader image it stands for when no closer one fits: its own key for a category image. */
    val category: String = "",
    /** For a variant, the food image it is a form of; null otherwise. */
    val parent: String? = null,
    val url: String = "",
)

/** Reads an enum by its API value; a value newer than the SDK becomes [unknown] instead of failing the response. */
internal open class LenientEnumSerializer<T : Enum<T>>(
    serialName: String,
    private val entries: List<T>,
    private val unknown: T,
    private val wire: (T) -> String,
) : KSerializer<T> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor(serialName, PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): T {
        val value = decoder.decodeString()
        return entries.firstOrNull { wire(it) == value } ?: unknown
    }

    override fun serialize(encoder: Encoder, value: T) = encoder.encodeString(wire(value))
}

internal object FoodTypeSerializer : LenientEnumSerializer<FoodType>(
    "io.studio93.foodapi.FoodType", FoodType.entries, FoodType.UNKNOWN, { it.value },
)

internal object NutrientFlagSerializer : LenientEnumSerializer<NutrientFlag>(
    "io.studio93.foodapi.NutrientFlag", NutrientFlag.entries, NutrientFlag.UNKNOWN, { it.value },
)

internal object ImageMatchSerializer : LenientEnumSerializer<ImageMatch>(
    "io.studio93.foodapi.ImageMatch", ImageMatch.entries, ImageMatch.UNKNOWN, { it.value },
)

internal object ImageTierSerializer : LenientEnumSerializer<ImageTier>(
    "io.studio93.foodapi.ImageTier", ImageTier.entries, ImageTier.UNKNOWN, { it.value },
)

/** Nutrients are a JSON object of numbers and nulls. */
internal object NutrientsSerializer : KSerializer<Nutrients> {
    private val delegate = MapSerializer(String.serializer(), Double.serializer().nullable)

    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun deserialize(decoder: Decoder): Nutrients = Nutrients(delegate.deserialize(decoder))

    override fun serialize(encoder: Encoder, value: Nutrients) = delegate.serialize(encoder, value.values)
}
