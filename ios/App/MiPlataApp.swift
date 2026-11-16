import SwiftUI
import Foundation

// MARK: - Datos

struct Bolsillo: Identifiable, Codable {
    var id = UUID()
    var nombre: String
    var monto: Int = 0
}

struct Movimiento: Identifiable, Codable {
    var id = UUID()
    var fecha = Date()
    var descripcion: String
    var monto: Int
    var ingreso: Bool
    var categoria: String
    var bolsilloID: UUID?
    var planID: UUID
}

struct Datos: Codable {
    var configurado = false
    var planID = UUID()
    var saldoInicial = 0
    var cuentas = 0
    var ahorro = 0
    var hasta = Date()
    var bolsillos: [Bolsillo] = [
        Bolsillo(nombre: "Bencina"),
        Bolsillo(nombre: "Comida"),
        Bolsillo(nombre: "Joda / salidas"),
        Bolsillo(nombre: "Otros"),
        Bolsillo(nombre: "Gustos / snacks")
    ]
    var movimientos: [Movimiento] = []

    var movimientosActuales: [Movimiento] {
        movimientos.filter { $0.planID == planID }
    }

    var saldo: Int {
        movimientosActuales.reduce(saldoInicial) {
            $0 + ($1.ingreso ? $1.monto : -$1.monto)
        }
    }

    var disponible: Int {
        saldo - cuentas - ahorro
    }

    var vencido: Bool {
        Calendar.current.startOfDay(for: hasta)
            < Calendar.current.startOfDay(for: Date())
    }

    func restante(_ bolsillo: Bolsillo) -> Int {
        let gastado = movimientosActuales
            .filter { !$0.ingreso && $0.bolsilloID == bolsillo.id }
            .reduce(0) { $0 + $1.monto }
        return bolsillo.monto - gastado
    }
}

func pesos(_ monto: Int) -> String {
    monto.formatted(
        .currency(code: "CLP")
        .locale(Locale(identifier: "es_CL"))
        .precision(.fractionLength(0))
    )
}

func montoValido(_ texto: String) -> Int? {
    let limpio = texto.trimmingCharacters(in: .whitespaces)
    guard !limpio.isEmpty,
          limpio.allSatisfy({ "0123456789".contains($0) }),
          let valor = Int(limpio),
          valor <= 1_000_000_000 else {
        return nil
    }
    return valor
}

// MARK: - Guardado local

final class Caja: ObservableObject {
    @Published private(set) var datos = Datos()
    @Published var error: String?
    private var lecturaFallida = false

    private var archivo: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("mi-plata.json")
    }

    init() {
        guard FileManager.default.fileExists(
            atPath: archivo.path
        ) else { return }

        do {
            let contenido = try Data(contentsOf: archivo)
            datos = try JSONDecoder().decode(Datos.self, from: contenido)
        } catch {
            lecturaFallida = true
            self.error = """
            No se pudieron leer tus datos. No se sobrescribirá \
            el archivo existente.
            """
        }
    }

    @discardableResult
    func guardar(_ nuevos: Datos) -> Bool {
        guard !lecturaFallida else {
            error = "No podemos guardar hasta recuperar el archivo existente."
            return false
        }

        do {
            let contenido = try JSONEncoder().encode(nuevos)
            try contenido.write(to: archivo, options: .atomic)
            datos = nuevos
            return true
        } catch {
            self.error = "No se pudo guardar. Intenta nuevamente."
            return false
        }
    }

    func agregar(
        descripcion: String,
        monto: Int,
        ingreso: Bool,
        bolsillo: Bolsillo
    ) -> Bool {
        var nuevos = datos
        let movimiento = Movimiento(
            descripcion: descripcion,
            monto: monto,
            ingreso: ingreso,
            categoria: ingreso ? "Ingreso" : bolsillo.nombre,
            bolsilloID: ingreso ? nil : bolsillo.id,
            planID: datos.planID
        )
        nuevos.movimientos.insert(movimiento, at: 0)
        return guardar(nuevos)
    }

    func respaldo() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(datos),
              let texto = String(data: data, encoding: .utf8) else {
            return ""
        }
        return texto
    }
}

// MARK: - App

@main
struct MiPlataApp: App {
    @StateObject private var caja = Caja()

    var body: some Scene {
        WindowGroup {
            Principal()
                .environmentObject(caja)
                .tint(.teal)
                .alert(
                    "Revisa el guardado",
                    isPresented: Binding(
                        get: { caja.error != nil },
                        set: { if !$0 { caja.error = nil } }
                    )
                ) {
                    Button("Entendido", role: .cancel) {}
                } message: {
                    Text(caja.error ?? "")
                }
        }
    }
}

struct Principal: View {
    var body: some View {
        TabView {
            Inicio()
                .tabItem {
                    Label("Inicio", systemImage: "house.fill")
                }

            Historial()
                .tabItem {
                    Label("Historial", systemImage: "list.bullet")
                }

            EvaluarCompra()
                .tabItem {
                    Label("¿Me alcanza?", systemImage: "cart")
                }
        }
    }
}

// MARK: - Inicio

struct Inicio: View {
    @EnvironmentObject var caja: Caja
    @State private var mostrarPlan = false
    @State private var mostrarGasto = false

    var dias: Int {
        max(
            1,
            (Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: caja.datos.hasta)
            ).day ?? 0) + 1
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if caja.datos.configurado {
                    Section {
                        Text("Disponible para gastar")
                            .font(.headline)

                        Text(pesos(caja.datos.disponible))
                            .font(.system(
                                size: 40,
                                weight: .bold,
                                design: .rounded
                            ))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundColor(
                                caja.datos.disponible < 0 ? .red : .teal
                            )

                        Text(
                            "Hasta el \(caja.datos.hasta.formatted(date: .abbreviated, time: .omitted))"
                        )

                        if caja.datos.vencido {
                            Text("Tu período terminó. Prepara un nuevo reparto.")
                                .foregroundColor(.orange)
                        } else {
                            Text(
                                "\(pesos(max(0, caja.datos.disponible) / dias)) por día orientativamente"
                            )
                            .foregroundColor(.secondary)
                        }

                        Text("Incluye comida, bencina, salidas y gustos.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        Button("Registrar gasto o ingreso") {
                            mostrarGasto = true
                        }
                        .disabled(caja.datos.vencido)
                    }

                    Section("Mi reparto") {
                        ForEach(caja.datos.bolsillos) { bolsillo in
                            HStack {
                                Text(bolsillo.nombre)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(pesos(caja.datos.restante(bolsillo)))
                                        .foregroundColor(
                                            caja.datos.restante(bolsillo) < 0
                                                ? .red : .primary
                                        )
                                    Text("de \(pesos(bolsillo.monto))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Section("Dinero protegido") {
                        fila("Saldo registrado", caja.datos.saldo)
                        fila("Cuentas pendientes", caja.datos.cuentas)
                        fila("Ahorro", caja.datos.ahorro)
                        Text("""
                        Las cuentas se reservan manualmente. Si pagas una, \
                        registra el gasto y actualiza la reserva para no \
                        descontarla dos veces.
                        """)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }

                    Section {
                        Button("Editar reservas") {
                            mostrarPlan = true
                        }
                        NavigationLink("Crear un nuevo reparto") {
                            PlanEditor(nuevo: true)
                        }
                    }
                } else {
                    Section {
                        Text("Parte con lo que tienes hoy")
                            .font(.title2.bold())
                        Text("""
                        Ingresa tu saldo y separa cuánto dejarás para \
                        cuentas, ahorro y cada tipo de gasto.
                        """)
                        Button("Ingresar mi saldo") {
                            mostrarPlan = true
                        }
                    }
                }

                Section("Guardado en este dispositivo") {
                    Text("""
                    Funciona sin internet. No se conecta al banco ni \
                    comparte tus datos con otros teléfonos.
                    """)
                    .font(.footnote)

                    if caja.datos.configurado {
                        ShareLink(
                            item: caja.respaldo(),
                            subject: Text("Respaldo Mi Plata")
                        ) {
                            Label(
                                "Compartir copia de mis datos",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        Text("""
                        Conserva una copia antes de reinstalar. \
                        Esta versión exporta el respaldo como texto JSON.
                        """)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Mi Plata")
            .sheet(isPresented: $mostrarPlan) {
                NavigationStack {
                    PlanEditor(nuevo: !caja.datos.configurado)
                }
            }
            .sheet(isPresented: $mostrarGasto) {
                NavigationStack {
                    RegistrarMovimiento()
                }
            }
        }
    }

    private func fila(_ titulo: String, _ monto: Int) -> some View {
        HStack {
            Text(titulo)
            Spacer()
            Text(pesos(monto))
        }
    }
}

// MARK: - Campos de dinero

struct CampoMonto: View {
    let titulo: String
    @Binding var texto: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo)
                .font(.subheadline)

            TextField("Monto en pesos, sin puntos", text: $texto)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach([0, 5000, 10000, 25000, 50000, 100000], id: \.self) {
                        valor in
                        Button(pesos(valor)) {
                            texto = String(valor)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Configurar el plan

struct PlanEditor: View {
    @EnvironmentObject var caja: Caja
    @Environment(\.dismiss) private var cerrar
    let nuevo: Bool

    @State private var saldo = ""
    @State private var cuentas = "0"
    @State private var ahorro = "0"
    @State private var hasta = Date()
    @State private var montos = Array(repeating: "0", count: 5)
    @State private var aviso = ""

    var body: some View {
        Form {
            if nuevo {
                Section("¿Cuánto tienes?") {
                    CampoMonto(titulo: "Saldo actual del banco", texto: $saldo)
                    DatePicker(
                        "Debe durar hasta",
                        selection: $hasta,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )
                    Text("""
                    El saldo debe incluir el dinero que vas a reservar. \
                    No ingreses aquí el cupo de una tarjeta.
                    """)
                    .font(.footnote)
                }
            }

            Section("¿Cuánto quieres apartar?") {
                CampoMonto(titulo: "Cuentas aún por pagar", texto: $cuentas)
                CampoMonto(titulo: "Ahorro protegido", texto: $ahorro)
            }

            if nuevo {
                Section("¿Cuánto gastarás en cada categoría?") {
                    ForEach(caja.datos.bolsillos.indices, id: \.self) { indice in
                        CampoMonto(
                            titulo: caja.datos.bolsillos[indice].nombre,
                            texto: $montos[indice]
                        )
                    }
                    Text("""
                    Confirmar inicia un reparto nuevo desde el saldo \
                    indicado. El historial anterior se conserva.
                    """)
                    .font(.footnote)
                }
            }

            if !aviso.isEmpty {
                Section {
                    Text(aviso).foregroundColor(.red)
                }
            }

            Section {
                Button(nuevo ? "Guardar mi reparto" : "Guardar reservas") {
                    guardar()
                }
            }
        }
        .navigationTitle(nuevo ? "Mi reparto" : "Mis reservas")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { cerrar() }
            }
        }
        .onAppear {
            saldo = String(caja.datos.saldo)
            cuentas = String(caja.datos.cuentas)
            ahorro = String(caja.datos.ahorro)
            montos = caja.datos.bolsillos.map { String($0.monto) }
            hasta = Calendar.current.date(
                byAdding: .day,
                value: 30,
                to: Date()
            ) ?? Date()
        }
    }

    private func guardar() {
        guard let c = montoValido(cuentas),
              let a = montoValido(ahorro) else {
            aviso = "Escribe montos válidos, sin puntos ni signos."
            return
        }

        var datos = caja.datos
        datos.cuentas = c
        datos.ahorro = a

        if nuevo {
            guard let s = montoValido(saldo) else {
                aviso = "Ingresa un saldo válido."
                return
            }

            let valores = montos.compactMap { montoValido($0) }
            guard valores.count == datos.bolsillos.count else {
                aviso = "Revisa los montos de las categorías."
                return
            }

            guard c + a + valores.reduce(0, +) <= s else {
                aviso = "El reparto supera tu saldo. Reduce algún monto."
                return
            }

            datos.saldoInicial = s
            datos.planID = UUID()
            datos.hasta = hasta
            datos.configurado = true

            for indice in datos.bolsillos.indices {
                datos.bolsillos[indice].monto = valores[indice]
            }
        }

        if caja.guardar(datos) {
            cerrar()
        }
    }
}

// MARK: - Registrar compras e ingresos

struct RegistrarMovimiento: View {
    @EnvironmentObject var caja: Caja
    @Environment(\.dismiss) private var cerrar

    @State private var descripcion = ""
    @State private var monto = ""
    @State private var ingreso = false
    @State private var categoria = 0
    @State private var aviso = ""

    var body: some View {
        Form {
            Section {
                Toggle("Es un ingreso", isOn: $ingreso)

                TextField(
                    ingreso ? "Ejemplo: sueldo" : "Ejemplo: Snickers",
                    text: $descripcion
                )

                CampoMonto(titulo: "Monto", texto: $monto)

                if !ingreso {
                    Picker("Descontar de", selection: $categoria) {
                        ForEach(caja.datos.bolsillos.indices, id: \.self) {
                            indice in
                            Text(caja.datos.bolsillos[indice].nombre)
                                .tag(indice)
                        }
                    }

                    Text("""
                    El gasto se descuenta una vez del saldo y también \
                    reduce lo restante de la categoría.
                    """)
                    .font(.footnote)
                } else {
                    Text("""
                    Aumenta tu saldo disponible. No cambia automáticamente \
                    los límites asignados a tus categorías.
                    """)
                    .font(.footnote)
                }
            }

            if !aviso.isEmpty {
                Section {
                    Text(aviso).foregroundColor(.red)
                }
            }

            Section {
                Button("Guardar movimiento") {
                    guardar()
                }
            }
        }
        .navigationTitle(ingreso ? "Nuevo ingreso" : "Nuevo gasto")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { cerrar() }
            }
        }
    }

    private func guardar() {
        let nombre = descripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty,
              let valor = montoValido(monto),
              valor > 0 else {
            aviso = "Escribe una descripción y un monto mayor que cero."
            return
        }

        let bolsillo = caja.datos.bolsillos[categoria]
        if caja.agregar(
            descripcion: nombre,
            monto: valor,
            ingreso: ingreso,
            bolsillo: bolsillo
        ) {
            cerrar()
        }
    }
}

// MARK: - Historial

struct Historial: View {
    @EnvironmentObject var caja: Caja

    var body: some View {
        NavigationStack {
            List {
                if caja.datos.movimientos.isEmpty {
                    Text("Todavía no registras movimientos.")
                        .foregroundColor(.secondary)
                }

                ForEach(caja.datos.movimientos) { movimiento in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(movimiento.descripcion)
                                .font(.headline)
                            Spacer()
                            Text(
                                (movimiento.ingreso ? "+" : "−")
                                    + pesos(movimiento.monto)
                            )
                            .foregroundColor(
                                movimiento.ingreso ? .green : .primary
                            )
                        }

                        Text(movimiento.categoria)
                            .font(.subheadline)

                        Text(
                            movimiento.fecha.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Mi historial")
        }
    }
}

// MARK: - Revisar antes de comprar

struct EvaluarCompra: View {
    @EnvironmentObject var caja: Caja
    @State private var precio = ""
    @State private var categoria = 0

    var body: some View {
        NavigationStack {
            Form {
                if !caja.datos.configurado {
                    Text("Primero ingresa tu saldo y reparto en Inicio.")
                } else if caja.datos.vencido {
                    Text("Tu reparto terminó. Crea uno nuevo antes de evaluar.")
                } else {
                    Section("Compra al contado") {
                        CampoMonto(titulo: "Precio total", texto: $precio)

                        Picker("Categoría", selection: $categoria) {
                            ForEach(caja.datos.bolsillos.indices, id: \.self) {
                                indice in
                                Text(caja.datos.bolsillos[indice].nombre)
                                    .tag(indice)
                            }
                        }
                    }

                    if let valor = montoValido(precio), valor > 0 {
                        resultado(valor)
                    }

                    Section {
                        Text("""
                        Esta revisión usa tu saldo, tus reservas y el \
                        límite de la categoría. No conoce deudas o gastos \
                        que no hayas registrado. No evalúa compras en cuotas.
                        """)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("¿Me alcanza?")
        }
    }

    private func resultado(_ precio: Int) -> some View {
        let bolsillo = caja.datos.bolsillos[categoria]
        let limite = caja.datos.restante(bolsillo)
        let alcanza = precio <= caja.datos.disponible && precio <= limite

        return Section("Resultado") {
            Label(
                alcanza ? "Cabe en tu reparto" : "No cabe en tu reparto",
                systemImage: alcanza
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundColor(alcanza ? .green : .red)

            Text("Disponible después: \(pesos(caja.datos.disponible - precio))")
            Text("En esta categoría quedarían: \(pesos(limite - precio))")
            Text("Consultar no registra la compra.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
