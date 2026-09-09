/**
 * ProntoOrderLookup
 * -----------------
 * Accion invocable para el "Agente Pronto" (Agentforce NGA).
 *
 * Resuelve "Donde esta mi pedido?" localizando la Person Account del cliente por
 * su email (PersonEmail) o por su Pronto Customer Id (p.ej. "PA-1003") y
 * devolviendo los datos del ultimo pedido almacenados en los campos Last_Order_*.
 *
 * Devuelve outputs planos (String/Boolean) para evitar la necesidad de
 * complex_data_type_name en el Agent Script y para que el LLM pueda mostrarlos
 * directamente. No lanza excepciones: ante cualquier problema devuelve
 * encontrado=false y un mensaje explicativo.
 */
public with sharing class ProntoOrderLookup {

    public class Request {
        @InvocableVariable(
            label='Identificador del cliente'
            description='Email del cliente o Pronto Customer Id (p.ej. PA-1003).'
            required=true)
        public String identificador;
    }

    public class Response {
        @InvocableVariable(label='Encontrado')
        public Boolean encontrado = false;
        @InvocableVariable(label='Nombre del cliente')
        public String nombreCliente = '';
        @InvocableVariable(label='Id del pedido')
        public String pedidoId = '';
        @InvocableVariable(label='Restaurante')
        public String restaurante = '';
        @InvocableVariable(label='Articulos del pedido')
        public String articulos = '';
        @InvocableVariable(label='Estado (codigo)')
        public String estado = '';
        @InvocableVariable(label='Estado (texto)')
        public String estadoTexto = '';
        @InvocableVariable(label='Total del pedido (EUR)')
        public String totalEur = '';
        @InvocableVariable(label='Fecha del pedido')
        public String fechaPedido = '';
        @InvocableVariable(label='Nivel de fidelidad')
        public String nivelFidelidad = '';
        @InvocableVariable(label='Mensaje')
        public String mensaje = '';
    }

    // Traduccion de los codigos de estado (picklist Last_Order_Status__c) a texto ES.
    private static final Map<String, String> ESTADO_TEXTO = new Map<String, String>{
        'preparing'  => 'En preparacion en el restaurante',
        'in_transit' => 'En camino con el repartidor',
        'delivered'  => 'Entregado',
        'cancelled'  => 'Cancelado'
    };

    @InvocableMethod(
        label='Pronto: Consultar ultimo pedido'
        description='Localiza al cliente por email o Pronto Customer Id y devuelve el estado y detalle de su ultimo pedido.')
    public static List<Response> lookup(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        // Normaliza los identificadores de entrada (una sola pasada, sin SOQL en bucle).
        List<String> emails = new List<String>();
        List<String> customerIds = new List<String>();
        List<String> normalized = new List<String>();
        for (Request req : requests) {
            String raw = (req != null && req.identificador != null) ? req.identificador.trim() : '';
            normalized.add(raw);
            if (String.isBlank(raw)) {
                continue;
            }
            if (raw.contains('@')) {
                emails.add(raw);
            } else {
                customerIds.add(raw.toUpperCase());
            }
        }

        // Consulta unica (batch) de todas las cuentas candidatas.
        Map<String, Account> byEmail = new Map<String, Account>();
        Map<String, Account> byCustomerId = new Map<String, Account>();
        if (!emails.isEmpty() || !customerIds.isEmpty()) {
            for (Account acc : [
                SELECT Id, Name, PersonEmail, Pronto_Customer_Id__c, Loyalty_Tier__c,
                       Last_Order_Id__c, Last_Order_Date__c, Last_Order_Restaurant__c,
                       Last_Order_Items__c, Last_Order_Total_EUR__c, Last_Order_Status__c
                FROM Account
                WHERE Pronto_Customer_Id__c IN :customerIds
                   OR PersonEmail IN :emails
            ]) {
                if (String.isNotBlank(acc.PersonEmail)) {
                    byEmail.put(acc.PersonEmail.toLowerCase(), acc);
                }
                if (String.isNotBlank(acc.Pronto_Customer_Id__c)) {
                    byCustomerId.put(acc.Pronto_Customer_Id__c.toUpperCase(), acc);
                }
            }
        }

        for (String raw : normalized) {
            results.add(buildResponse(raw, byEmail, byCustomerId));
        }
        return results;
    }

    private static Response buildResponse(String raw,
                                          Map<String, Account> byEmail,
                                          Map<String, Account> byCustomerId) {
        Response res = new Response();
        if (String.isBlank(raw)) {
            res.mensaje = 'No se ha indicado ningun identificador. Pide al cliente su email o su Pronto Customer Id (p.ej. PA-1003).';
            return res;
        }

        Account acc = raw.contains('@')
            ? byEmail.get(raw.toLowerCase())
            : byCustomerId.get(raw.toUpperCase());

        if (acc == null) {
            res.mensaje = 'No he encontrado ningun cliente con "' + raw + '". Verifica el email o el Pronto Customer Id e intentalo de nuevo.';
            return res;
        }

        res.encontrado = true;
        res.nombreCliente = acc.Name;
        res.nivelFidelidad = acc.Loyalty_Tier__c;

        if (String.isBlank(acc.Last_Order_Id__c)) {
            res.mensaje = 'El cliente ' + acc.Name + ' no tiene ningun pedido registrado.';
            return res;
        }

        res.pedidoId = acc.Last_Order_Id__c;
        res.restaurante = acc.Last_Order_Restaurant__c;
        res.articulos = acc.Last_Order_Items__c;
        res.estado = acc.Last_Order_Status__c;
        res.estadoTexto = ESTADO_TEXTO.containsKey(acc.Last_Order_Status__c)
            ? ESTADO_TEXTO.get(acc.Last_Order_Status__c)
            : acc.Last_Order_Status__c;
        if (acc.Last_Order_Total_EUR__c != null) {
            res.totalEur = String.valueOf(acc.Last_Order_Total_EUR__c.setScale(2)) + ' EUR';
        }
        if (acc.Last_Order_Date__c != null) {
            res.fechaPedido = acc.Last_Order_Date__c.format();
        }
        res.mensaje = 'Pedido ' + res.pedidoId + ' de ' + res.restaurante + ': ' + res.estadoTexto + '.';
        return res;
    }
}
