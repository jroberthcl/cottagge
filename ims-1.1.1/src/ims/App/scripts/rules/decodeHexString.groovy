def hexToAscii(String hex) {
    def output = new StringBuilder()

    // Recorrer cada 2 caracteres (1 byte)
    for (int i = 0; i < hex.length(); i += 2) {
        def str = hex.substring(i, i + 2)
        // Convertir a entero base 16 y luego a carácter ASCII
        output.append((char) Integer.parseInt(str, 16))
    }

    return output.toString()
}

// Tu cadena hexadecimal
def hexString = nme.Norm_RecordId

// Ejecutar la conversión
def decodedText = hexToAscii(hexString)

nme.Norm_RecordId = decodedText