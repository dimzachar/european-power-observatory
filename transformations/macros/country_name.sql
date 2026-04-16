{% macro country_name_from_code(code_expression) -%}
case {{ code_expression }}
    when 'DE' then 'Germany'
    when 'DK' then 'Denmark'
    when 'ES' then 'Spain'
    when 'FR' then 'France'
    when 'GR' then 'Greece'
    when 'IT' then 'Italy'
    when 'PL' then 'Poland'
    when 'SE' then 'Sweden'
    else {{ code_expression }}
end
{%- endmacro %}
