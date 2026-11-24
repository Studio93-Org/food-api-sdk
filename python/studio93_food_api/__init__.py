"""Python client for the Studio93 Food API (v2): typo-tolerant food search, autocomplete, barcode lookups (plain
barcodes, GS1 codes and GS1 Digital Links) and detailed nutrition for every serving.

Create one client and share it; it keeps connections open between requests and retries what is safe to retry::

    from studio93_food_api import FoodApiClient, FoodApiNotFound

    client = FoodApiClient(os.environ["FOOD_API_KEY"], user_agent="my-service/1.0")

    page = client.search("greek yogurt")
    for food in page.foods:
        print(food.name, food.servings[0].nutrients.calories)

    try:
        food = client.food_by_barcode("3017624010701")
    except FoodApiNotFound:
        ...  # No source knows this barcode: an answer, not a failure

A server calling the API for its users passes each user's IP address (``client.with_client_ip(ip)`` or
``client_ip=``), so search ranks for the user's country rather than the server's.

The API reference is at https://api.studio93.io/food/docs.
"""

from .client import DEFAULT_BASE_URL, VERSION, FoodApiClient
from .errors import (
    FoodApiBadRequest,
    FoodApiError,
    FoodApiForbidden,
    FoodApiHTTPError,
    FoodApiInvalidInput,
    FoodApiNetworkError,
    FoodApiNotFound,
    FoodApiRateLimited,
    FoodApiServerError,
    FoodApiTimeoutError,
    FoodApiUnauthorized,
    FoodApiUnavailable,
)
from .models import (
    AutocompleteResult,
    Food,
    FoodImage,
    FoodSource,
    FoodType,
    ImageEntry,
    ImageGroup,
    ImageMatch,
    ImageSet,
    ImageTier,
    NutrientDefinition,
    NutrientFlag,
    NutrientList,
    Nutrients,
    NutrientStat,
    NutrientStats,
    OtherNutrient,
    SearchPage,
    Serving,
    Suggestion,
)

__version__ = VERSION

__all__ = [
    "VERSION",
    "DEFAULT_BASE_URL",
    "FoodApiClient",
    "FoodApiError",
    "FoodApiHTTPError",
    "FoodApiBadRequest",
    "FoodApiUnauthorized",
    "FoodApiForbidden",
    "FoodApiNotFound",
    "FoodApiRateLimited",
    "FoodApiUnavailable",
    "FoodApiServerError",
    "FoodApiNetworkError",
    "FoodApiTimeoutError",
    "FoodApiInvalidInput",
    "AutocompleteResult",
    "Food",
    "FoodImage",
    "FoodSource",
    "FoodType",
    "ImageEntry",
    "ImageGroup",
    "ImageMatch",
    "ImageSet",
    "ImageTier",
    "NutrientDefinition",
    "NutrientFlag",
    "NutrientList",
    "Nutrients",
    "NutrientStat",
    "NutrientStats",
    "OtherNutrient",
    "SearchPage",
    "Serving",
    "Suggestion",
]
