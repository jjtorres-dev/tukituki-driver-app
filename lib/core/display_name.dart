/// Formatea un nombre para mostrar en UI: nombre + inicial del primer
/// apellido ("Mark Landeo" -> "Mark L."). Nunca se persiste el
/// resultado en Backend ni en almacenamiento local — se deriva solo
/// para presentación, en cada punto donde se necesite mostrarlo.
///
/// Contrato equivalente a `displayCompactName`/`displayCompactNameFromInitial`
/// de `tukituki-passenger-app` (R4.2/R4.3): mismo comportamiento
/// defensivo, para que "Juan P." se vea igual desde ambas apps.
///
/// Defensivo ante datos legacy/incompletos: recorta espacios en los
/// extremos, nunca produce "null" ni un "." suelto, y nunca introduce
/// espacios dobles. Si no hay nombre, devuelve cadena vacía — el
/// llamador decide qué mostrar en ese caso (p.ej. omitir la fila del
/// nombre), en vez de que este helper imponga un placeholder como
/// "Pasajero"/"Conductor"/"Usuario".
String displayCompactName(String? firstName, String? lastName) {
  final first = firstName?.trim() ?? '';
  final last = lastName?.trim() ?? '';

  if (first.isEmpty) {
    return '';
  }

  if (last.isEmpty) {
    return first;
  }

  final initial = last[0].toUpperCase();

  return '$first $initial.';
}

/// Igual que [displayCompactName], pero para contratos donde Backend ya
/// envía la inicial del apellido pre-derivada (p.ej. "L."), en vez del
/// apellido completo — el caso del Passenger visto por el Driver desde
/// R4.3 (`DriverRideOfferPassengerDto.lastNameInitial`,
/// `RideAssignedPassengerResponseDto.lastNameInitial`).
///
/// Mismas garantías defensivas que [displayCompactName]: recorta
/// espacios, nunca produce "null" ni un "." suelto/doble, y si no hay
/// nombre devuelve cadena vacía en vez de inventar un placeholder.
String displayCompactNameFromInitial(
  String? firstName,
  String? lastNameInitial,
) {
  final first = firstName?.trim() ?? '';
  final initial = lastNameInitial?.trim() ?? '';

  if (first.isEmpty) {
    return '';
  }

  if (initial.isEmpty) {
    return first;
  }

  return '$first $initial';
}
