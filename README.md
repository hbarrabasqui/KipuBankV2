# 🏦 KipuBankV2 - Contrato Bancario Multi-Token

Contrato bancario descentralizado que extiende **KipuBank** original con soporte multi-token, oráculos **Chainlink** y control de acceso avanzado.

---

## 🚀 Despliegue Rápido en Sepolia

### 🧩 Prerrequisitos
- MetaMask configurado con la red **Sepolia**
- ETH de prueba desde un [Sepolia Faucet](https://sepoliafaucet.com)

### ⚙️ Pasos para Despliegue
1. Conectar **Remix** a **MetaMask**
2. Seleccionar **Environment:** `Injected Provider - MetaMask`
3. Asegurarse de que **MetaMask** esté en la red **Sepolia**

### 🧱 Parámetros del Constructor
Completar los campos con los siguientes valores:

```solidity
_limiteGlobalUSD = 1000000000        // 1000 USD (6 decimales)
_limiteETH       = 100000000000000000  // 0.1 ETH (en wei)
_ethUsdFeed      = 0x694AA1769357215DE4FAC081bf1f309aDC325306  // Feed ETH/USD (Sepolia)
_admin           = [TU_DIRECCION_METAMASK]  // Dirección del administrador

✅ Desplegar y Verificar

Confirmar la transacción en MetaMask

Verificar el contrato en Etherscan Sepolia (pestaña “Verify & Publish” en https://sepolia.etherscan.io
)

🏗️ Arquitectura y Mejoras
🔹 Características Principales

✅ Soporte Multi-Token: ETH + ERC20 con balances separados
✅ Límites en USD: Control de capacidad global en dólares
✅ Oráculos Chainlink: Precios en tiempo real para conversiones
✅ Control de Acceso: Roles administrativos con OpenZeppelin
✅ Seguridad: ReentrancyGuard y SafeERC20

🔗 Direcciones en Sepolia Testnet
📊 Tokens ERC20 Disponibles

(Contratos de tokens reales en Sepolia que los usuarios pueden depositar)

Token	Dirección	Descripción
ETH	0x0000000000000000000000000000000000000000	ETH nativo (no ERC20)
USDC	0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238	Contrato token USDC
LINK	0x779877A7B0D9E8603169DdbD7836e478b4624789	Contrato token LINK

🔄 Feeds Chainlink de Precios

(Oráculos que proveen datos de precios en tiempo real)

Feed	Dirección	Par
ETH/USD	0x694AA1769357215DE4FAC081bf1f309aDC325306	ETH/USD
USDC/USD	0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E	USDC/USD
LINK/USD	0xc59E3633BAAC79493d908e63626716e204A45EdF	LINK/USD

🧠 Diferencia clave:
Los tokens son activos que los usuarios depositan; los feeds son oráculos que proveen precios para las conversiones.

💻 Interacción con el Contrato
👤 Para Usuarios
// Depositar ETH
depositarETH({ value: 10000000000000000 }) // 0.01 ETH

// Depositar ERC20
depositarERC20(usdcAddress, 1000000) // 1 USDC

// Consultar saldos
saldoDe(ethAddress, userAddress)       // ETH (usar address(0))
saldoDe(usdcAddress, userAddress)      // USDC
saldoDeUSD(tokenAddress, userAddress)  // En USD

🛠️ Para Administradores
// Registrar nuevo token (requiere token + feed)
registrarToken(tokenAddress, feedAddress, decimals, limite)

// Gestionar límites
actualizarLimiteToken(tokenAddress, nuevoLimite)

// Configurar feeds
actualizarFeedToken(tokenAddress, nuevoFeed)

🛡️ Características de Seguridad

ReentrancyGuard: Protección contra ataques de reentrada

SafeERC20: Transferencias seguras de tokens

Validaciones: Límites por transacción y globales

AccessControl: Funciones administrativas restringidas

📊 Funciones de Consulta
// Balances y conversiones
calcularTotalBalanceUSD()    // Total del banco en USD
capacidadDisponibleUSD()     // Capacidad restante
convertirAUSD(token, monto)  // Conversión a USD

// Información del sistema
obtenerTokensRegistrados()   // Lista de tokens
obtenerLimiteToken(token)    // Límite por token

🔧 Configuración Post-Despliegue
Registrar Tokens ERC20

Ejemplo: Registrar USDC con su feed correspondiente:

registrarToken(
  0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // Token USDC
  0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E,  // Feed USDC/USD
  6,                                            // Decimales del token
  500000000                                     // Límite: 500 USDC
)

Probar Funcionalidades

✅ Depósitos y retiros de ETH y ERC20
✅ Verificación de límites por token
✅ Conversión a USD en tiempo real
✅ Validación de eventos emitidos

📄 Licencia: MIT
🔗 Red: Sepolia Testnet
🧱 Repositorio: KipuBankV2 en GitHub

✉️ Autor: Horacio Barrabasqui
