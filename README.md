
# KipuBankV2

## Mejoras Implementadas

### Control de Acceso con Roles
Sistema de roles con OpenZeppelin AccessControl que restringe funciones administrativas como registro de tokens y actualización de oráculos.

### Soporte Multi-Token con Mappings Anidados
Mappings anidados (`mapping(address => mapping(address => uint256))`) para gestionar balances separados de múltiples tokens ERC20 por usuario.

### Integración con Oráculos Chainlink
Conexión con Chainlink Price Feeds para conversiones en tiempo real de ETH y tokens a USD, permitiendo contabilidad estandarizada.

### Sistema de Conversión de Decimales
Normalización de valores a 6 decimales (estándar USDC) con manejo automático de tokens con diferentes decimales.

## Instrucciones de Despliegue (desde Remix)

### 1. Configuración Inicial
- Acceder a [https://remix.ethereum.org](https://remix.ethereum.org)
- Crear carpeta `/src` y subir archivo **KipuBankV2.sol**

### 2. Compilación
- Seleccionar compilador Solidity (versión `0.8.26`)
- Compilar **KipuBankV2.sol** sin errores

### 3. Despliegue en Sepolia
- **Environment:** "Injected Provider - MetaMask"
- **Network:** Sepolia Testnet
- **Parámetros del constructor:**
  - `_limitePorTx`: 1000000000000000000 (1 ETH)
  - `_bankCap`: 5000000000000000000 (5 ETH)
  - `_ethUsdFeed`: 0x694AA1769357215DE4FAC081bf1f309aDC325306
  - `_admin`: Tu dirección de MetaMask

### 4. Verificación en Block Explorer
- Copiar dirección del contrato desplegado
- Verificar en [Sepolia Etherscan](https://sepolia.etherscan.io)
- Publicar código fuente completo

## Interacción con el Contrato

### Operaciones para Usuarios
```solidity
// Depositar ETH
depositar({ value: 100000000000000000 }) // 0.1 ETH

// Depositar tokens ERC20
depositERC20(tokenAddress, 1000000)

// Retirar tokens
withdrawERC20(tokenAddress, 500000)

// Consultar balances
balanceOfToken(tokenAddress, userAddress)

// Conversiones a USD
convertEthToUSD(1000000000000000000) // 1 ETH
convertTokenToUSD(tokenAddress, 1000000)

### Operaciones para Administradores
// Registrar token ERC20
registerToken(tokenAddress, feedAddress, 18)

// Actualizar feed ETH/USD
setEthFeed(feedAddress)

// Retiro de emergencia
emergencyWithdrawToken(tokenAddress, destination)

### Decisiones de Diseño y Trade-offs

| Decisión                                             | Motivo                                                      | Trade-off                                                            |
| ---------------------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------- |
| Uso de `AccessControl` de OpenZeppelin               | Permite múltiples roles y mayor flexibilidad que `Ownable`. | Aumenta el consumo de gas en ciertas operaciones.                    |
| Implementación de oráculos de Chainlink              | Aporta datos de precios confiables.                         | Depende de la disponibilidad de los feeds y aumenta el costo de gas. |
| Estandarización de decimales (6 decimales tipo USDC) | Facilita comparaciones entre activos.                       | Requiere adaptar tokens con distintos decimales.                     |
| Herencia del contrato original                       | Reutiliza lógica probada del KipuBank anterior.             | Aumenta la complejidad del código.                                   |
| Uso de `SafeERC20`                                   | Evita errores comunes en transferencias ERC20.              | Leve sobrecarga de gas.                                              |
