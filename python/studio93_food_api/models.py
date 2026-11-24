"""Response models of the Food API (v2).

Parsing is lenient: fields the SDK doesn't know are ignored, and enum values newer than the SDK parse as
``UNKNOWN``, so newer API versions keep working with older SDKs. Every model is a frozen dataclass:
``dataclasses.asdict(food)`` gives plain data that ``json.dumps`` accepts.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Mapping, Optional

__all__ = [
    "FoodType",
    "NutrientFlag",
    "ImageMatch",
    "ImageTier",
    "Food",
    "FoodImage",
    "FoodSource",
    "Serving",
    "Nutrients",
    "SearchPage",
    "Suggestion",
    "AutocompleteResult",
    "NutrientStats",
    "NutrientStat",
    "NutrientList",
    "NutrientDefinition",
    "OtherNutrient",
    "ImageSet",
    "ImageGroup",
    "ImageEntry",
]


class FoodType(str, Enum):
    """Whether a food is a generic food (an apple, cooked rice) or a branded product."""

    GENERIC = "generic"
    BRAND = "brand"
    UNKNOWN = "unknown"  # A type this version of the SDK doesn't know

    @classmethod
    def parse(cls, value: Any) -> "FoodType":
        return _parse_enum(cls, value, cls.UNKNOWN)


class NutrientFlag(str, Enum):
    """Marks a nutrient value that isn't a plain measurement. A value without a flag is as precise as its source
    says nothing otherwise."""

    UPPER_BOUND = "upper_bound"  # The label said "less than": the real amount is at most the value (show "< 1 g")
    APPROXIMATE = "approximate"  # Rounded or estimated on the label, for example from a % daily value
    ASSUMED_ZERO = "assumed_zero"  # Set to 0 by the source without being measured
    UNKNOWN = "unknown"  # A flag this version of the SDK doesn't know

    @classmethod
    def parse(cls, value: Any) -> "NutrientFlag":
        return _parse_enum(cls, value, cls.UNKNOWN)


class ImageMatch(str, Enum):
    """How closely a food's image shows it."""

    VARIANT = "variant"  # This food in its form or flavour (whole milk, not just milk)
    FOOD = "food"  # This food
    CATEGORY = "category"  # The kind of food it is, for example cheese for a gouda
    FALLBACK = "fallback"  # Nothing fitted, so a generic plate, drink or meal; apps may prefer to show none
    UNKNOWN = "unknown"  # A value this version of the SDK doesn't know: treat it like CATEGORY

    @classmethod
    def parse(cls, value: Any) -> "ImageMatch":
        return _parse_enum(cls, value, cls.UNKNOWN)


class ImageTier(str, Enum):
    """How specific an image of the set is."""

    CATEGORY = "category"  # A kind of food (cheese)
    FOOD = "food"  # One food (cheddar)
    VARIANT = "variant"  # A form of a food (whole milk)
    UNKNOWN = "unknown"  # A tier this version of the SDK doesn't know

    @classmethod
    def parse(cls, value: Any) -> "ImageTier":
        return _parse_enum(cls, value, cls.UNKNOWN)


class Nutrients(Dict[str, Optional[float]]):
    """A serving's nutrient amounts by key, in the units :meth:`FoodApiClient.nutrients` lists.

    It is a dict: ``nutrients.get("magnesium")`` reads any key (None when unknown or absent). The core nutrients are
    always present, None when unknown, and have properties.
    """

    @classmethod
    def from_json(cls, value: Any) -> "Nutrients":
        return cls((str(k), _float(v)) for k, v in _dict(value).items())

    @property
    def calories(self) -> Optional[float]:  # kcal
        return self.get("calories")

    @property
    def protein(self) -> Optional[float]:  # g
        return self.get("protein")

    @property
    def carbohydrate(self) -> Optional[float]:  # g
        return self.get("carbohydrate")

    @property
    def fat(self) -> Optional[float]:  # g
        return self.get("fat")

    @property
    def sugar(self) -> Optional[float]:  # g
        return self.get("sugar")

    @property
    def fiber(self) -> Optional[float]:  # g
        return self.get("fiber")

    @property
    def saturated_fat(self) -> Optional[float]:  # g
        return self.get("saturated_fat")

    @property
    def monounsaturated_fat(self) -> Optional[float]:  # g
        return self.get("monounsaturated_fat")

    @property
    def polyunsaturated_fat(self) -> Optional[float]:  # g
        return self.get("polyunsaturated_fat")

    @property
    def cholesterol(self) -> Optional[float]:  # mg
        return self.get("cholesterol")

    @property
    def sodium(self) -> Optional[float]:  # mg
        return self.get("sodium")

    @property
    def potassium(self) -> Optional[float]:  # mg
        return self.get("potassium")

    @property
    def calcium(self) -> Optional[float]:  # mg
        return self.get("calcium")

    @property
    def iron(self) -> Optional[float]:  # mg
        return self.get("iron")

    @property
    def vitamin_a(self) -> Optional[float]:  # µg
        return self.get("vitamin_a")

    @property
    def vitamin_c(self) -> Optional[float]:  # mg
        return self.get("vitamin_c")

    @property
    def vitamin_d(self) -> Optional[float]:  # µg
        return self.get("vitamin_d")


@dataclass(frozen=True)
class FoodImage:
    """A picture of a food from the API's image set: a 256 px JPEG. The URL is public (it needs no API key) and never
    changes for a key, so it can be cached for good."""

    key: str  # "<group>/<slug>", as in FoodApiClient.images() ("dairy/cheddar")
    url: str
    match: ImageMatch  # How closely the image shows the food

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "FoodImage":
        return cls(key=_str(value.get("key")), url=_str(value.get("url")), match=ImageMatch.parse(value.get("match")))

    @property
    def is_fallback(self) -> bool:
        """Whether this is the generic picture used when nothing fitted the food (a plate, a drink); apps may prefer
        to show none."""
        return self.match is ImageMatch.FALLBACK


@dataclass(frozen=True)
class FoodSource:
    """Where a food's data comes from (USDA, CNF, FatSecret, OpenFoodFacts) and its ID there."""

    provider: str
    id: str

    @classmethod
    def from_json(cls, value: Any) -> "FoodSource":
        v = _dict(value)
        return cls(provider=_str(v.get("provider")), id=_str(v.get("id")))


@dataclass(frozen=True)
class Serving:
    """One way of measuring a food (a cup, 100 g, one bar), with the nutrients it contains."""

    description: str
    measurement: str
    metric_amount: Optional[float]
    metric_unit: str
    units: Optional[float]
    nutrients: Nutrients
    source_id: Optional[str] = None  # The source's own ID for the serving, when it has one
    # Whether the API worked this serving out from the source's ones (100 g, 1 oz, 1 fl oz, 1 cup, ...). Generic
    # servings come after the source's own.
    generic: bool = False

    @classmethod
    def from_json(cls, value: Any) -> "Serving":
        v = _dict(value)
        return cls(
            description=_str(v.get("description")),
            measurement=_str(v.get("measurement")),
            metric_amount=_float(v.get("metric_amount")),
            metric_unit=_str(v.get("metric_unit")),
            units=_float(v.get("units")),
            nutrients=Nutrients.from_json(v.get("nutrients")),
            source_id=_opt_str(v.get("source_id")),
            generic=v.get("generic") is True,
        )


@dataclass(frozen=True)
class Food:
    """One food in the catalog, with its nutrition per serving."""

    id: str
    name: str
    brand: Optional[str]
    type: FoodType
    barcodes: List[str]
    servings: List[Serving]
    source: FoodSource
    # What the source says about the food; None when unknown
    ingredients: Optional[str] = None
    category: Optional[str] = None
    # Everything else the source gives about the food, as text. See alternate_names.
    attributes: Dict[str, str] = field(default_factory=dict)
    # Nutrient values that aren't plain measurements, by nutrient key. They hold for every serving.
    nutrient_flags: Dict[str, NutrientFlag] = field(default_factory=dict)
    # A picture of the food; None in answers from before the API had images
    image: Optional[FoodImage] = None

    @classmethod
    def from_json(cls, value: Any) -> "Food":
        v = _dict(value)
        image = v.get("image")
        return cls(
            id=_required_str(v, "id"),
            name=_str(v.get("name")),
            brand=_opt_str(v.get("brand")),
            type=FoodType.parse(v.get("type")),
            barcodes=[b for b in _list(v.get("barcodes")) if isinstance(b, str)],
            servings=[Serving.from_json(s) for s in _list(v.get("servings"))],
            source=FoodSource.from_json(v.get("source")),
            ingredients=_opt_str(v.get("ingredients")),
            category=_opt_str(v.get("category")),
            attributes=_str_dict(v.get("attributes")),
            nutrient_flags={k: NutrientFlag.parse(f) for k, f in _str_dict(v.get("nutrient_flags")).items()},
            image=FoodImage.from_json(image) if isinstance(image, dict) else None,
        )

    @property
    def alternate_names(self) -> List[str]:
        """Other names the source gives the food ("pop", "soda" for cola)."""
        text = self.attributes.get("alternate_names", "")
        return [n.strip() for n in text.split(",") if n.strip()]

    def flag(self, nutrient: str) -> Optional[NutrientFlag]:
        """The flag of a nutrient value, or None when it has none."""
        return self.nutrient_flags.get(nutrient)


@dataclass(frozen=True)
class SearchPage:
    """One page of search results."""

    foods: List[Food]
    query: str  # The query as searched: lowercase, single spaces
    page: int
    limit: int
    total: int
    # "catalog", or "provider" when the catalog had no good match and the results came from an outside provider
    source: str
    # With regional ranking, the country whose foods ranked first among equally good matches (an ISO code such as
    # "CA"); None when none did
    region: Optional[str]
    # The brand the query names ("Coca-Cola" for "coke"), whose foods ranked first; None when it names none
    brand: Optional[str]
    cached: bool  # Whether the API answered from its cache


@dataclass(frozen=True)
class Suggestion:
    """An autocomplete match: enough to show in a list. Look the food up with FoodApiClient.food() when picked."""

    id: str
    name: str
    brand: Optional[str] = None

    @classmethod
    def from_json(cls, value: Any) -> "Suggestion":
        v = _dict(value)
        return cls(id=_required_str(v, "id"), name=_str(v.get("name")), brand=_opt_str(v.get("brand")))


@dataclass(frozen=True)
class AutocompleteResult:
    """The suggestions for what has been typed so far."""

    suggestions: List[Suggestion]
    query: str
    limit: int
    total: int  # How many foods match
    cached: bool


@dataclass(frozen=True)
class NutrientStat:
    """How one nutrient value was obtained. Amounts are per 100 g."""

    data_points: Optional[int] = None  # Samples the value comes from
    std_error: Optional[float] = None
    min: Optional[float] = None
    max: Optional[float] = None
    median: Optional[float] = None
    # The source's code for how the value was obtained, and what it means
    derivation: Optional[str] = None
    derivation_description: Optional[str] = None
    derivation_basis: Optional[str] = None
    footnote: Optional[str] = None
    updated: Optional[str] = None  # When the source last updated the value (yyyy-mm-dd)

    @classmethod
    def from_json(cls, value: Any) -> "NutrientStat":
        v = _dict(value)
        points = _float(v.get("data_points"))
        return cls(
            data_points=int(points) if points is not None else None,
            std_error=_float(v.get("std_error")),
            min=_float(v.get("min")),
            max=_float(v.get("max")),
            median=_float(v.get("median")),
            derivation=_opt_str(v.get("derivation")),
            derivation_description=_opt_str(v.get("derivation_description")),
            derivation_basis=_opt_str(v.get("derivation_basis")),
            footnote=_opt_str(v.get("footnote")),
            updated=_opt_str(v.get("updated")),
        )


@dataclass(frozen=True)
class NutrientStats:
    """What a food's source says about each of its nutrient values, per 100 g."""

    food_id: str
    per: str
    nutrients: Dict[str, NutrientStat]

    @classmethod
    def from_json(cls, value: Any) -> "NutrientStats":
        v = _dict(value)
        return cls(
            food_id=_required_str(v, "id"),
            per=_str(v.get("per"), "100 g"),
            nutrients={str(k): NutrientStat.from_json(s) for k, s in _dict(v.get("nutrients")).items()},
        )


@dataclass(frozen=True)
class NutrientDefinition:
    """A nutrient with a fixed key and unit."""

    key: str
    name: str
    unit: str
    group: str  # energy, macro, sugar, fat, mineral, vitamin or other
    core: bool  # Core nutrients are always present in a serving

    @classmethod
    def from_json(cls, value: Any) -> "NutrientDefinition":
        v = _dict(value)
        return cls(
            key=_required_str(v, "key"),
            name=_str(v.get("name")),
            unit=_str(v.get("unit")),
            group=_str(v.get("group")),
            core=v.get("core") is True,
        )


@dataclass(frozen=True)
class OtherNutrient:
    """A nutrient key without a fixed one, as its source described it."""

    key: str
    name: str
    unit: str
    source: str

    @classmethod
    def from_json(cls, value: Any) -> "OtherNutrient":
        v = _dict(value)
        return cls(
            key=_required_str(v, "key"),
            name=_str(v.get("name")),
            unit=_str(v.get("unit")),
            source=_str(v.get("source")),
        )


@dataclass(frozen=True)
class NutrientList:
    """Every nutrient key a serving can have."""

    # Nutrients with a fixed key and unit; the core ones are always present in a serving
    nutrients: List[NutrientDefinition]
    # Keys sources have given that don't have a fixed key yet ("usda_1018", "cnf_409", ...)
    other: List[OtherNutrient]

    @classmethod
    def from_json(cls, value: Any) -> "NutrientList":
        v = _dict(value)
        return cls(
            nutrients=[NutrientDefinition.from_json(n) for n in _list(v.get("nutrients"))],
            other=[OtherNutrient.from_json(n) for n in _list(v.get("other"))],
        )


@dataclass(frozen=True)
class ImageGroup:
    """A group of images, such as "Milk and dairy"."""

    key: str
    label: str

    @classmethod
    def from_json(cls, value: Any) -> "ImageGroup":
        v = _dict(value)
        return cls(key=_required_str(v, "key"), label=_str(v.get("label")))


@dataclass(frozen=True)
class ImageEntry:
    """One image of the set."""

    key: str  # "<group>/<slug>"
    label: str
    tier: ImageTier
    group: str  # The group's key
    category: str  # The broader image it stands for when no closer one fits: its own key for a category image
    url: str
    parent: Optional[str] = None  # For a variant, the food image it is a form of

    @classmethod
    def from_json(cls, value: Any) -> "ImageEntry":
        v = _dict(value)
        return cls(
            key=_required_str(v, "key"),
            label=_str(v.get("label")),
            tier=ImageTier.parse(v.get("tier")),
            group=_str(v.get("group")),
            category=_str(v.get("category")),
            url=_str(v.get("url")),
            parent=_opt_str(v.get("parent")) or None,
        )


@dataclass(frozen=True)
class ImageSet:
    """Every food image the API can give a food, for apps that bundle or prefetch them."""

    version: int  # Changes when the images are redrawn
    updated: str  # yyyy-mm-dd
    fallback: str  # The key of the image used when nothing fits a food
    groups: List[ImageGroup]
    images: List[ImageEntry]

    @classmethod
    def from_json(cls, value: Any) -> "ImageSet":
        v = _dict(value)
        version = _float(v.get("version"))
        return cls(
            version=int(version) if version is not None else 0,
            updated=_str(v.get("updated")),
            fallback=_str(v.get("fallback")),
            groups=[ImageGroup.from_json(g) for g in _list(v.get("groups"))],
            images=[ImageEntry.from_json(i) for i in _list(v.get("images"))],
        )

    def image(self, key: str) -> Optional[ImageEntry]:
        """The image with a key, or None when the set has none."""
        for entry in self.images:
            if entry.key == key:
                return entry
        return None


def _parse_enum(cls: Any, value: Any, unknown: Any) -> Any:
    try:
        return cls(value)
    except (ValueError, TypeError):
        return unknown


def _dict(value: Any) -> Dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _list(value: Any) -> List[Any]:
    return value if isinstance(value, list) else []


def _str(value: Any, default: str = "") -> str:
    return value if isinstance(value, str) else default


def _opt_str(value: Any) -> Optional[str]:
    return value if isinstance(value, str) else None


def _required_str(v: Mapping[str, Any], key: str) -> str:
    value = v.get(key)
    if not isinstance(value, str):
        raise ValueError("missing %r" % key)
    return value


def _float(value: Any) -> Optional[float]:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def _str_dict(value: Any) -> Dict[str, str]:
    return {str(k): v for k, v in _dict(value).items() if isinstance(v, str)}
