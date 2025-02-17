﻿CREATE OR REPLACE FUNCTION aplicar_movimientobanco(id_documento int)
RETURNS void AS $$

DECLARE
	id_clavefolio int;
	id_usuario int;
	id_cuentabancaria int;
        id_cuentabancaria1 int;
        id_cuentabancaria2 int;
	id_sucursal int;
	id_docban int;
	id_detalledocumento int;	
	id_concepto int;
	id_movimiento int;

	detalledoc CURSOR FOR SELECT "ID" FROM "Detalle_Documento" WHERE "Id_Documento" = id_documento;
	detalledocid "Detalle_Documento"%ROWTYPE;

	id_personafiscal int;
	subtotal numeric;
	saldo numeric;
	cantidad_retirar numeric;
	resultado_compara boolean;

BEGIN
    -- 1. Se consulta del documento dado como parametro el Concepto - Id_Concepto, Id_Movimiento(Entrada)
    EXECUTE 'SELECT "Documento"."Id_ClaveFolio", "Documento"."Id_Usuario", "Documento"."Id_ConceptoDocumento", "Detalle_Documento"."Id_PersonaFiscal", "Detalle_Documento"."Id_CuentaBancaria1", "Detalle_Documento"."Id_CuentaBancaria2", "Detalle_Documento"."Subtotal" FROM "Documento" INNER JOIN "Detalle_Documento" ON "Documento"."ID" = "Detalle_Documento"."Id_Documento" WHERE "Documento"."ID" =' || id_documento INTO id_clavefolio, id_usuario, id_concepto, id_personafiscal, id_cuentabancaria1, id_cuentabancaria2, subtotal;

    EXECUTE 'SELECT "Id_Movimiento" FROM "Documento_Concepto" WHERE "ID"='|| id_concepto INTO id_movimiento;

    -- 2. Del documento origen, tomando como base la informacion de Id_ClaveFolio, extrae Id_Sucursal
    EXECUTE 'SELECT "Id_Sucursal_Sistema" FROM "Numeracion_Folio" WHERE "Id_ClaveFolio" = ' || id_clavefolio INTO id_sucursal;

    IF id_movimiento = 1 THEN --Ingreso
       id_cuentabancaria := id_cuentabancaria1;
    ELSIF id_movimiento = 2 THEN --Egreso
       id_cuentabancaria := id_cuentabancaria2;
       cantidad_retirar := subtotal;
       EXECUTE 'SELECT comparar_saldobanco('||id_cuentabancaria||', '||cantidad_retirar||')' INTO resultado_compara;
       IF resultado_compara = 'F' THEN
	 -- No existen suficientes existencias en el almacen para cubrir la cantidad solicitada
        RAISE EXCEPTION 'DB_ERROR_04 --> %', resultado_compara;
       END IF;
    END IF;

	-- Se asume que el documento siempre contendra un detalle dado que sera creado por la aplicacion
	FOR detalledocid IN detalledoc LOOP
	  -- Se crea el documento de banco tomando como base el documento que invoco este procedimiento
	  -- Actualmente la funcion crear documento setea el id_documentoorigen a 0. Cambiar esto
          EXECUTE 'SELECT crear_documento('||id_sucursal||',''Flujo_Bancos'','||id_usuario||', '||id_documento||', '||id_concepto||')' INTO id_docban;

	  --  Inserta un registro en la tabla Detalle_Documento 
	  EXECUTE 'INSERT INTO "Detalle_Documento"("Id_Documento", "Id_PersonaFiscal", "Id_CuentaBancaria1", "Id_CuentaBancaria2","Subtotal") VALUES ('|| id_docban ||' ,'|| id_personafiscal ||', '|| id_cuentabancaria1 ||', '|| id_cuentabancaria2 ||','|| subtotal ||' )';

          -- De una vez actualizar el monto del documento de banco con el monto del documento origen
          EXECUTE 'UPDATE "Documento" SET "Monto" = '|| subtotal ||' WHERE "ID"='|| id_docban;

	  -- Actualiza las existencias del registro maestro para la ubicacion agregando la cantidad a ingresar
	  EXECUTE 'SELECT "Saldo" FROM "Cuenta_Bancaria" WHERE "ID" = '||id_cuentabancaria INTO saldo;

	  IF id_movimiento = 1 THEN -- Ingreso
	     -- Si el movimiento del documento es de ingreso
	     EXECUTE 'UPDATE "Cuenta_Bancaria" SET "Saldo" = ' ||saldo + subtotal||' WHERE "ID" = '||id_cuentabancaria;
	  ELSIF id_movimiento = 2 THEN -- Salida
	     -- Si el movimiento del documento es de egreso
	     EXECUTE 'UPDATE "Cuenta_Bancaria" SET "Saldo" = ' ||saldo - subtotal||' WHERE "ID" = '||id_cuentabancaria;
	  END IF;

	  EXECUTE 'SELECT aplicar_asiento('||id_docban||')';
	  EXECUTE 'SELECT cerrar_documento('||id_docban||')';
	END LOOP;
END;
$$ LANGUAGE PLPGSQL;
