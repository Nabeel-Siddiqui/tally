defmodule Tally.Finance.CategoryRuleTest do
  use ExUnit.Case, async: true

  alias Tally.Finance.CategoryRule

  describe "match/2" do
    test "returns the category of the first rule whose match_text is in the merchant" do
      rules = [%CategoryRule{match_text: "netflix", category: "Subscriptions"}]

      assert CategoryRule.match(rules, "Netflix.com") == "Subscriptions"
    end

    test "matches case-insensitively" do
      rules = [%CategoryRule{match_text: "NETFLIX", category: "Subscriptions"}]

      assert CategoryRule.match(rules, "netflix.com") == "Subscriptions"
    end

    test "returns nil when no rule matches" do
      rules = [%CategoryRule{match_text: "netflix", category: "Subscriptions"}]

      assert CategoryRule.match(rules, "Local Coffee Shop") == nil
    end

    test "the first matching rule in list order wins, not the most specific one" do
      rules = [
        %CategoryRule{match_text: "coffee", category: "Dining"},
        %CategoryRule{match_text: "local coffee shop", category: "Local Business"}
      ]

      assert CategoryRule.match(rules, "Local Coffee Shop") == "Dining"
    end

    test "an empty rule list never matches" do
      assert CategoryRule.match([], "Netflix.com") == nil
    end
  end
end
