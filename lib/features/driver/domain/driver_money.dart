/// Helpers de dinero en centavos enteros para el flujo de cobro en
/// efectivo (Checkpoint D). Nunca se usa `double` para reglas
/// monetarias (suficiencia, vuelto, quick amounts): todo pasa por
/// `int` (centavos) y solo se formatea a string decimal al final,
/// que es el formato exacto que Backend espera (`^\d+\.\d{2}$`).
library;

/// Convierte un string decimal (hasta 2 decimales, sin signo) a
/// centavos enteros. Retorna `null` si el formato no es un monto
/// válido (letras, negativos, más de 2 decimales, vacío).
int? parseAmountToCents(String value) {
  final trimmed = value.trim();

  if (trimmed.isEmpty) {
    return null;
  }

  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(trimmed);

  if (match == null) {
    return null;
  }

  final wholePart = int.tryParse(match.group(1)!);

  if (wholePart == null) {
    return null;
  }

  final fractionRaw = (match.group(2) ?? '').padRight(2, '0');
  final fractionPart = int.tryParse(fractionRaw) ?? 0;

  return (wholePart * 100) + fractionPart;
}

/// Formatea centavos enteros como string decimal con exactamente 2
/// decimales ("1050" -> "10.50"). Es el formato que Backend valida
/// con `^(0|[1-9]\d*)\.\d{2}$` en `ConfirmCashPaymentDto.cashReceived`.
String formatCentsAsDecimal(int cents) {
  final isNegative = cents < 0;
  final absCents = cents.abs();
  final whole = absCents ~/ 100;
  final fraction = (absCents % 100).toString().padLeft(2, '0');

  return '${isNegative ? '-' : ''}$whole.$fraction';
}

/// Escalera de montos de efectivo comunes, en centavos.
const List<int> _cashLadderCents = [500, 1000, 2000, 5000, 10000, 20000, 50000];

/// Salto entre múltiplos usado cuando el total supera toda la
/// escalera (S/ 100 = 10000 centavos).
const int _cashLadderOverflowStepCents = 10000;

/// Devuelve exactamente 3 montos sugeridos en centavos: el monto
/// exacto primero, seguido de los dos siguientes montos de efectivo
/// comunes estrictamente superiores. Si el total supera toda la
/// escalera (S/ 500), continúa en múltiplos de S/ 100. Nunca duplica
/// valores ni asume siempre 5/10/20.
List<int> quickAmountsForDueCents(int dueCents) {
  final amounts = <int>{dueCents};

  for (final step in _cashLadderCents) {
    if (amounts.length >= 3) {
      break;
    }

    if (step > dueCents) {
      amounts.add(step);
    }
  }

  if (amounts.length < 3) {
    var multiple =
        ((dueCents ~/ _cashLadderOverflowStepCents) + 1) *
        _cashLadderOverflowStepCents;

    while (amounts.length < 3) {
      if (multiple > dueCents) {
        amounts.add(multiple);
      }

      multiple += _cashLadderOverflowStepCents;
    }
  }

  return amounts.toList()..sort();
}
