{% macro celsius_to_fahrenheit(celsius_column) %}
    round(({{ celsius_column }} * 9.0 / 5.0) + 32, 2)
{% endmacro %}