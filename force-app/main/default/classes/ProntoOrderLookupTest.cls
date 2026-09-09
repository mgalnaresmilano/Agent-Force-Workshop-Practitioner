@IsTest
private class ProntoOrderLookupTest {

    private static Id personAccountRecordTypeId() {
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true
            LIMIT 1
        ]) {
            return rt.Id;
        }
        return null;
    }

    @TestSetup
    static void seed() {
        Id rtId = personAccountRecordTypeId();
        if (rtId == null) {
            return; // Person Accounts no habilitadas: los tests de "no encontrado" siguen siendo validos.
        }
        Account pa = new Account(
            RecordTypeId = rtId,
            FirstName = 'Test',
            LastName = 'Cliente',
            PersonEmail = 'test.cliente@example.com',
            Pronto_Customer_Id__c = 'PA-9001',
            Loyalty_Tier__c = 'Gold',
            Last_Order_Id__c = 'ORD-99001',
            Last_Order_Date__c = Date.newInstance(2026, 9, 1),
            Last_Order_Restaurant__c = 'La Huerta Verde',
            Last_Order_Items__c = 'Ensalada de quinoa, Hummus',
            Last_Order_Total_EUR__c = 18.40,
            Last_Order_Status__c = 'in_transit'
        );
        insert pa;

        // Cliente sin pedido registrado.
        Account sinPedido = new Account(
            RecordTypeId = rtId,
            FirstName = 'Sin',
            LastName = 'Pedido',
            PersonEmail = 'sin.pedido@example.com',
            Pronto_Customer_Id__c = 'PA-9002',
            Loyalty_Tier__c = 'Bronze'
        );
        insert sinPedido;
    }

    private static ProntoOrderLookup.Response callOne(String identificador) {
        ProntoOrderLookup.Request req = new ProntoOrderLookup.Request();
        req.identificador = identificador;
        List<ProntoOrderLookup.Response> out =
            ProntoOrderLookup.lookup(new List<ProntoOrderLookup.Request>{ req });
        System.assertEquals(1, out.size(), 'Debe devolver una respuesta por peticion');
        return out[0];
    }

    @IsTest
    static void lookupPorCustomerId() {
        if (personAccountRecordTypeId() == null) {
            return;
        }
        Test.startTest();
        ProntoOrderLookup.Response res = callOne('pa-9001'); // en minusculas -> se normaliza
        Test.stopTest();

        System.assertEquals(true, res.encontrado, 'Debe encontrar el cliente por Pronto Customer Id');
        System.assertEquals('ORD-99001', res.pedidoId);
        System.assertEquals('in_transit', res.estado);
        System.assertEquals('En camino con el repartidor', res.estadoTexto);
        System.assertEquals('18.40 EUR', res.totalEur);
        System.assertEquals('Gold', res.nivelFidelidad);
        System.assert(res.mensaje.contains('ORD-99001'), 'El mensaje debe citar el pedido');
    }

    @IsTest
    static void lookupPorEmail() {
        if (personAccountRecordTypeId() == null) {
            return;
        }
        Test.startTest();
        ProntoOrderLookup.Response res = callOne('Test.Cliente@Example.com'); // mayus -> case-insensitive
        Test.stopTest();

        System.assertEquals(true, res.encontrado, 'Debe encontrar el cliente por email');
        System.assertEquals('La Huerta Verde', res.restaurante);
    }

    @IsTest
    static void clienteSinPedido() {
        if (personAccountRecordTypeId() == null) {
            return;
        }
        ProntoOrderLookup.Response res = callOne('PA-9002');
        System.assertEquals(true, res.encontrado, 'El cliente existe');
        System.assertEquals('', res.pedidoId, 'No debe haber pedido');
        System.assert(res.mensaje.contains('no tiene ningun pedido'), 'Mensaje de sin pedido');
    }

    @IsTest
    static void clienteNoEncontrado() {
        ProntoOrderLookup.Response res = callOne('PA-0000');
        System.assertEquals(false, res.encontrado, 'No debe encontrar cliente inexistente');
        System.assert(res.mensaje.contains('No he encontrado'), 'Mensaje de no encontrado');
    }

    @IsTest
    static void identificadorEnBlanco() {
        ProntoOrderLookup.Response res = callOne('   ');
        System.assertEquals(false, res.encontrado);
        System.assert(res.mensaje.contains('No se ha indicado'), 'Mensaje de identificador vacio');
    }

    @IsTest
    static void listaVaciaYnula() {
        System.assertEquals(0,
            ProntoOrderLookup.lookup(new List<ProntoOrderLookup.Request>()).size(),
            'Lista vacia -> sin resultados');
        System.assertEquals(0, ProntoOrderLookup.lookup(null).size(),
            'Null -> sin resultados');
    }

    @IsTest
    static void multiplesPeticionesEnBatch() {
        if (personAccountRecordTypeId() == null) {
            return;
        }
        ProntoOrderLookup.Request r1 = new ProntoOrderLookup.Request();
        r1.identificador = 'PA-9001';
        ProntoOrderLookup.Request r2 = new ProntoOrderLookup.Request();
        r2.identificador = 'desconocido@example.com';
        Test.startTest();
        List<ProntoOrderLookup.Response> out =
            ProntoOrderLookup.lookup(new List<ProntoOrderLookup.Request>{ r1, r2 });
        Test.stopTest();
        System.assertEquals(2, out.size());
        System.assertEquals(true, out[0].encontrado);
        System.assertEquals(false, out[1].encontrado);
    }
}
