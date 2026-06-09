module ApplicationHelper
  # Pagy 43.x removed Pagy::Frontend. Navigation is now rendered via instance
  # methods on the Pagy object itself (e.g. `@pagy.series_nav`), so no helper
  # mixin is required here.

  def line_item_category_class(category)
    case category
    when "material"  then "bg-blue-100 text-blue-700"
    when "labor"     then "bg-green-100 text-green-700"
    when "alternate" then "bg-purple-100 text-purple-700"
    when "buy_out"   then "bg-orange-100 text-orange-700"
    when "other"     then "bg-slate-100 text-slate-600"
    else "bg-slate-100 text-slate-600"
    end
  end
end
