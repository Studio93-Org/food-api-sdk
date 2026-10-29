package foodapi

import "strings"

// FoodType says whether a food is a generic food (an apple, cooked rice) or a branded product.
type FoodType string

const (
	FoodTypeGeneric FoodType = "generic"
	FoodTypeBrand   FoodType = "brand"
)

// Food is one food in the catalog, with its nutrition per serving.
type Food struct {
	ID       string    `json:"id"`
	Name     string    `json:"name"`
	Brand    *string   `json:"brand"`
	Type     FoodType  `json:"type"`
	Barcodes []string  `json:"barcodes"`
	Servings []Serving `json:"servings"`
	Source   Source    `json:"source"`
	// What the source says about the food; nil when unknown
	Ingredients *string `json:"ingredients"`
	Category    *string `json:"category"`
	// Everything else the source gives about the food, as text. See AlternateNames.
	Attributes map[string]string `json:"attributes"`
	// Nutrient values that aren't plain measurements, by nutrient key. They hold for every serving.
	NutrientFlags map[string]NutrientFlag `json:"nutrient_flags"`
}

// AlternateNames returns the other names the source gives the food ("pop", "soda" for cola), or nil.
func (f Food) AlternateNames() []string {
	text := strings.TrimSpace(f.Attributes["alternate_names"])
	if text == "" {
		return nil
	}
	var names []string
	for _, name := range strings.Split(text, ",") {
		if name = strings.TrimSpace(name); name != "" {
			names = append(names, name)
		}
	}
	return names
}

// Flag returns the flag of a nutrient value, or "" when it has none.
func (f Food) Flag(nutrient string) NutrientFlag { return f.NutrientFlags[nutrient] }

// Source is where a food's data comes from (USDA, CNF, FatSecret, OpenFoodFacts) and its ID there.
type Source struct {
	Provider string `json:"provider"`
	ID       string `json:"id"`
}

// Serving is one way of measuring a food (a cup, 100 g, one bar), with the nutrients it contains.
type Serving struct {
	Description  string    `json:"description"`
	Measurement  string    `json:"measurement"`
	MetricAmount *float64  `json:"metric_amount"`
	MetricUnit   string    `json:"metric_unit"`
	Units        *float64  `json:"units"`
	Nutrients    Nutrients `json:"nutrients"`
	SourceID     string    `json:"source_id,omitempty"` // The source's own ID for the serving, when it has one
	// A generic serving (100 g, 1 oz, 1 fl oz, 1 cup, …) the API worked out from the source's servings; generic
	// servings come after the source's own
	Generic bool `json:"generic,omitempty"`
}

// Nutrients holds a serving's nutrient amounts by key, in the units Client.Nutrients lists. The core nutrients
// are always present, nil when unknown; other nutrients are present only when known.
type Nutrients map[string]*float64

// Get returns a nutrient's amount, and false when it is unknown.
func (n Nutrients) Get(key string) (float64, bool) {
	v := n[key]
	if v == nil {
		return 0, false
	}
	return *v, true
}

// Core nutrient keys: every serving has them, null when unknown.
const (
	Calories           = "calories"            // kcal
	Protein            = "protein"             // g
	Carbohydrate       = "carbohydrate"        // g
	Fat                = "fat"                 // g
	Sugar              = "sugar"               // g
	Fiber              = "fiber"               // g
	SaturatedFat       = "saturated_fat"       // g
	MonounsaturatedFat = "monounsaturated_fat" // g
	PolyunsaturatedFat = "polyunsaturated_fat" // g
	Cholesterol        = "cholesterol"         // mg
	Sodium             = "sodium"              // mg
	Potassium          = "potassium"           // mg
	Calcium            = "calcium"             // mg
	Iron               = "iron"                // mg
	VitaminA           = "vitamin_a"           // µg
	VitaminC           = "vitamin_c"           // mg
	VitaminD           = "vitamin_d"           // µg
)

// NutrientFlag marks a nutrient value that isn't a plain measurement. A value without a flag is as precise as its
// source says nothing otherwise.
type NutrientFlag string

const (
	// FlagUpperBound: the label said "less than", so the real amount is at most the value (show "< 1 g").
	FlagUpperBound NutrientFlag = "upper_bound"
	// FlagApproximate: rounded or estimated on the label, for example worked out from a % daily value.
	FlagApproximate NutrientFlag = "approximate"
	// FlagAssumedZero: set to 0 by the source without being measured.
	FlagAssumedZero NutrientFlag = "assumed_zero"
)

// SearchPage is one page of search results.
type SearchPage struct {
	Foods []Food
	Query string // The query as searched: lowercase, single spaces
	Page  int
	Limit int
	Total int64
	// "catalog", or "provider" when the catalog had no good match and the results came from an outside provider
	Source string
	Cached bool // Answered from the API's cache
}

// Suggestion is an autocomplete match: enough to show in a list. Look the food up with Client.Food when picked.
type Suggestion struct {
	ID    string  `json:"id"`
	Name  string  `json:"name"`
	Brand *string `json:"brand"`
}

// Autocomplete is the suggestions for what has been typed so far.
type Autocomplete struct {
	Suggestions []Suggestion
	Query       string
	Limit       int
	Total       int64 // How many foods match
	Cached      bool
}

// NutrientStats is what a food's source says about each of its nutrient values, per 100 g.
type NutrientStats struct {
	FoodID    string                  `json:"id"`
	Per       string                  `json:"per"`
	Nutrients map[string]NutrientStat `json:"nutrients"`
}

// NutrientStat describes how one nutrient value was obtained. Amounts are per 100 g.
type NutrientStat struct {
	DataPoints *int     `json:"data_points,omitempty"` // Samples the value comes from
	StdError   *float64 `json:"std_error,omitempty"`
	Min        *float64 `json:"min,omitempty"`
	Max        *float64 `json:"max,omitempty"`
	Median     *float64 `json:"median,omitempty"`
	// The source's code for how the value was obtained, and what it means
	Derivation            string `json:"derivation,omitempty"`
	DerivationDescription string `json:"derivation_description,omitempty"`
	DerivationBasis       string `json:"derivation_basis,omitempty"`
	Footnote              string `json:"footnote,omitempty"`
	Updated               string `json:"updated,omitempty"` // yyyy-mm-dd
}

// NutrientList is every nutrient key a serving can have.
type NutrientList struct {
	// Nutrients with a fixed key and unit; the core ones are always present in a serving
	Nutrients []NutrientDef `json:"nutrients"`
	// Keys sources have given that don't have a fixed key yet ("usda_1018", "cnf_409", …)
	Other []OtherNutrient `json:"other"`
}

// NutrientDef is a nutrient with a fixed key and unit.
type NutrientDef struct {
	Key   string `json:"key"`
	Name  string `json:"name"`
	Unit  string `json:"unit"`
	Group string `json:"group"` // energy, macro, sugar, fat, mineral, vitamin, other
	Core  bool   `json:"core"`
}

// OtherNutrient is a nutrient key without a fixed one, as its source described it.
type OtherNutrient struct {
	Key    string `json:"key"`
	Name   string `json:"name"`
	Unit   string `json:"unit"`
	Source string `json:"source"`
}
