Rails.application.config.burden_constants = {
  mileage_rate:      BigDecimal("0.67"),   # Federal rate; update annually
  round_trip_factor: 2,
  hotel_rate:        BigDecimal("150.00"), # Per person per night
  airfare_rate:      BigDecimal("400.00")  # Per person per ticket
}.freeze
