// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title KipuBankV2
 * @author Horacio Barrabasqui
 * @notice Extensión de KipuBank con soporte multi-token, control de acceso y Oráculos Chainlink.
 * @dev Hereda KipuBank . Añade mappings anidados, SafeERC20 para ERC20,
 *      registro de tokens con su Chainlink Feed, y conversión de decimales a 6 decimales (USDC-like).
 */
import "./KipuBank.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/*
 KipuBankV2: Acá heredo el KipuBank anterior
*/
contract KipuBankV2 is KipuBank, AccessControl {
    using SafeERC20 for IERC20;

    // --------------------------------------------------
    // Tipos, constantes y variables
    // --------------------------------------------------
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice mapping anidado: token => user => balance (en unidades del token)
    mapping(address => mapping(address => uint256)) private s_tokenBalances;

    /// @notice total por token (en unidades del token)
    mapping(address => uint256) public s_totalTokenBalances;

    /// @notice registro de feeds por token (token => Chainlink Aggregator)
    mapping(address => AggregatorV3Interface) public s_tokenFeeds;

    /// @notice decimales configurados por token (p. ej. USDC=6, tokens ERC20 estándar=18)
    mapping(address => uint8) public s_tokenDecimals;

    /// @notice factor decimal para normalizar a 6 decimales 
    uint256 public constant DECIMAL_FACTOR = 1 * 10 ** 20; 

    // address(0) para representar ETH
    address public constant ETH_ADDRESS = address(0);

    // Chainlink feed para ETH/USD 
    AggregatorV3Interface public s_ethUsdFeed;

    // Eventos
    event KipuBankV2_TokenDeposit(address indexed token, address indexed user, uint256 amount);
    event KipuBankV2_TokenWithdraw(address indexed token, address indexed user, uint256 amount);
    event KipuBankV2_TokenRegistered(address indexed token, address feed, uint8 decimals);
    event KipuBankV2_EthFeedUpdated(address feed);

    // Errores
    error KipuBankV2_TokenNoRegistrado(address token);
    error KipuBankV2_SaldoInsuficienteToken(address token, address user, uint256 balance, uint256 requested);
    error KipuBankV2_TransferenciaTokenFallida();

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------
    /**
     * @param _limitePorTx pasado al constructor padre (por transacción para ETH)
     * @param _bankCap pasado al padre.
     * @param _ethUsdFeed dirección del Chainlink ETH/USD .
     * @param _admin dirección que obtiene rol ADMIN_ROLE
     */
    constructor(
        uint256 _limitePorTx,
        uint256 _bankCap,
        address _ethUsdFeed,
        address _admin
    ) KipuBank(_limitePorTx, _bankCap) {
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, msg.sender); // también el deployer por defecto
        if (_ethUsdFeed != address(0)) {
            s_ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        }
    }

    // --------------------------------------------------
    // Admin: registro de tokens y feeds
    // --------------------------------------------------
    /**
     * @notice Registrar un token ERC20 para permitir depósitos/retiros y asignarle un Chainlink Feed.
     * @param token dirección del token ERC20 (no 0)
     * @param feed dirección del AggregatorV3Interface que devuelve precio token/USD (8 decimals en la mayoría de feeds)
     * @param decimals cantidad de decimales del token ERC20 (p.ej. USDC=6, ERC20 usual=18)
     */
    function registerToken(address token, address feed, uint8 decimals) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "token zero not allowed");
        s_tokenFeeds[token] = AggregatorV3Interface(feed);
        s_tokenDecimals[token] = decimals;
        emit KipuBankV2_TokenRegistered(token, feed, decimals);
    }

    function setEthFeed(address feed) external onlyRole(ADMIN_ROLE) {
        s_ethUsdFeed = AggregatorV3Interface(feed);
        emit KipuBankV2_EthFeedUpdated(feed);
    }

    // --------------------------------------------------
    // Depositar ERC20
    // --------------------------------------------------
    /**
     * @notice Depositar tokens ERC20 al vault del usuario.
     * @param token dirección del token ERC20 (debe estar registrado)
     * @param amount cantidad en unidades del token (no 0)
     */
    function depositERC20(address token, uint256 amount) external {
        if (s_tokenFeeds[token] == AggregatorV3Interface(address(0))) revert KipuBankV2_TokenNoRegistrado(token);
        if (amount == 0) revert KipuBank_MontoCero();

        // Efecto: actualizamos balances internos (checks-effects-interactions)
        s_tokenBalances[token][msg.sender] += amount;
        s_totalTokenBalances[token] += amount;

        // Transferir tokens al contrato (pull)
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit KipuBankV2_TokenDeposit(token, msg.sender, amount);
    }

    // --------------------------------------------------
    // Retirar ERC20
    // --------------------------------------------------
    /**
     * @notice Retirar tokens ERC20 desde tu bóveda.
     * @param token dirección del token registrado
     * @param amount cantidad a retirar (en unidades del token)
     */
    function withdrawERC20(address token, uint256 amount) external {
        uint256 bal = s_tokenBalances[token][msg.sender];
        if (bal < amount) revert KipuBankV2_SaldoInsuficienteToken(token, msg.sender, bal, amount);

        // Checks-effects-interactions
        s_tokenBalances[token][msg.sender] = bal - amount;
        s_totalTokenBalances[token] -= amount;

        // Transferir token
        IERC20(token).safeTransfer(msg.sender, amount);

        emit KipuBankV2_TokenWithdraw(token, msg.sender, amount);
    }

    // --------------------------------------------------
    // Vistas auxiliares
    // --------------------------------------------------
    /**
     * @notice Obtener balance de un usuario para un token (o ETH denotado por address(0))
     */
    function balanceOfToken(address token, address user) external view returns (uint256) {
        if (token == ETH_ADDRESS) {        
            return 0;
        }
        return s_tokenBalances[token][user];
    }

    /**
     * @notice Convierte una cantidad de ETH (wei) a USD con 6 decimales (USDC-like).
     * @dev Usa el Chainlink ETH/USD feed. 
     */
    function convertEthToUSD(uint256 ethAmountWei) public view returns (uint256) {
        AggregatorV3Interface feed = s_ethUsdFeed;
        require(address(feed) != address(0), "ETH feed not set");
        (, int256 price, , , ) = feed.latestRoundData();
        if (price <= 0) revert KipuBank_TransaccionNoPermitida(); // simple guard
        // price tiene (p.ej.) 8 decimales; ethAmountWei tiene 18 -> multiplicar y normalizar a 6 decimales:
        // converted = (ethAmountWei * uint256(price)) / DECIMAL_FACTOR
        // DECIMAL_FACTOR = 1e20 en el material (para llegar a 6 decimales).
        return (ethAmountWei * uint256(price)) / DECIMAL_FACTOR;
    }

    /**
     * @notice Convierte una cantidad de token a USDC-like (6 decimales) usando el feed registrado.
     * @dev asume feed token/USD y que el feed devuelve valores con 8 decimales (ajusta si tu feed es distinto).
     */
    function convertTokenToUSD(address token, uint256 tokenAmount) public view returns (uint256) {
        AggregatorV3Interface feed = s_tokenFeeds[token];
        if (address(feed) == address(0)) revert KipuBankV2_TokenNoRegistrado(token);
        (, int256 price, , , ) = feed.latestRoundData();
        if (price <= 0) revert KipuBank_TransaccionNoPermitida();

        uint8 tokenDec = s_tokenDecimals[token];
        // tokenAmount tiene tokenDec decimales; price tiene (p.ej.) 8 decimals; quiero resultado en 6 decimals.
        // normalized = (tokenAmount * uint256(price)) / (10 ** tokenDec) * adjustment => reorganizo para evitar overflow:
        // converted = (tokenAmount * uint256(price)) / (10 ** tokenDec) / (10 ** (8 - 6)) => simplified below.
        // Safer formula: (tokenAmount * uint256(price)) / (10 ** tokenDec) / (10 ** (feedDecimals - 6))
        uint256 feedDecimals = 8; // bastante comun para Chainlink USD feeds
        // Compute divisor = 10**tokenDec * 10**(feedDecimals - 6)
        uint256 divisor;
        if (feedDecimals >= 6) {
            divisor = (10 ** tokenDec) * (10 ** (feedDecimals - 6));
        } else {
            divisor = (10 ** tokenDec) / (10 ** (6 - feedDecimals));
        }
        return (tokenAmount * uint256(price)) / divisor;
    }

    // --------------------------------------------------
    // Utilities / notas
    // --------------------------------------------------
    /**
     * @notice (ADMIN) Permitir retirar tokens en bloque en caso de emergencia.
     * @dev ejemplo de función administrativa: envía todo el token al admin.
     */
    function emergencyWithdrawToken(address token, address to) external onlyRole(ADMIN_ROLE) {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(token).safeTransfer(to, bal);
        }
    }

}

