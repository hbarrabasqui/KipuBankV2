// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @author Horacio Barrabasqui
 * @notice Contrato bancario multi-token con límites globales en USD, soporte para ETH/ERC20 y oráculos Chainlink
 * @dev Versión completa y funcional sin errores de compilación
 */
contract KipuBankV2 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================
    // ===== CONSTANTES ====
    // ====================
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    address public constant ETH_ADDRESS = address(0);
    uint256 private constant INTERNAL_DECIMALS = 6; // USDC-like para cálculos internos
    uint256 private constant MAX_ITERATIONS = 50;

    // ====================
    // ====== ERRORS ======
    // ====================
    error KipuBankV2_BancoSinCapacidad();
    error KipuBankV2_SaldoInsuficiente();
    error KipuBankV2_MontoMayorAlLimite();
    error KipuBankV2_TransferenciaFallida();
    error KipuBankV2_MontoCero();
    error KipuBankV2_TransaccionNoPermitida();
    error KipuBankV2_TokenNoRegistrado(address token);
    error KipuBankV2_FeedNoConfigurado();
    error KipuBankV2_PrecioInvalido();
    error KipuBankV2_TokenYaRegistrado();
    error KipuBankV2_IteracionDemasiadoGrande();

    // ====================
    // ===== VARIABLES ====
    // ====================
    uint256 public immutable i_limiteGlobalUSD;
    mapping(address => uint256) public s_limitesPorToken;
    mapping(address => mapping(address => uint256)) private s_balances;
    mapping(address => uint256) public s_totalBalances;
    uint256 public s_totalDepositos;
    uint256 public s_totalRetiros;
    mapping(address => address) public s_tokenFeeds;
    mapping(address => uint8) public s_tokenDecimals;
    mapping(address => bool) public s_tokensRegistrados;
    address[] public s_tokenList;

    // ====================
    // ===== EVENTOS ======
    // ====================
    event Deposito(address indexed token, address indexed usuario, uint256 monto, uint256 valorUSD);
    event Retiro(address indexed token, address indexed usuario, uint256 monto, uint256 valorUSD);
    event TokenRegistrado(address indexed token, address feed, uint8 decimals, uint256 limite);
    event LimiteTokenActualizado(address indexed token, uint256 limite);
    event FeedTokenActualizado(address indexed token, address feed);
    event RecepcionETH(address indexed remitente, uint256 monto);

    // ====================
    // ===== MODIFIERS ====
    // ====================
    modifier montoMayorQueCero(uint256 _monto) {
        if (_monto == 0) revert KipuBankV2_MontoCero();
        _;
    }

    modifier soloTokenRegistrado(address _token) {
        if (!s_tokensRegistrados[_token] && _token != ETH_ADDRESS) 
            revert KipuBankV2_TokenNoRegistrado(_token);
        _;
    }

    // ====================
    // ===== CONSTRUCTOR ==
    // ====================
    constructor(
        uint256 _limiteGlobalUSD,
        uint256 _limiteETH,
        address _ethUsdFeed,
        address _admin
    ) {
        require(_ethUsdFeed != address(0), "Feed ETH requerido");
        require(_admin != address(0), "Admin requerido");
        
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, msg.sender);
        
        i_limiteGlobalUSD = _limiteGlobalUSD;
        
        // Registrar ETH por defecto
        s_tokensRegistrados[ETH_ADDRESS] = true;
        s_tokenFeeds[ETH_ADDRESS] = _ethUsdFeed;
        s_tokenDecimals[ETH_ADDRESS] = 18;
        s_limitesPorToken[ETH_ADDRESS] = _limiteETH;
        s_tokenList.push(ETH_ADDRESS);
        
        emit TokenRegistrado(ETH_ADDRESS, _ethUsdFeed, 18, _limiteETH);
    }

    // ====================
    // ===== FUNCIONES ADMIN
    // ====================
    function registrarToken(
        address _token,
        address _feed,
        uint8 _decimals,
        uint256 _limiteTransaccion
    ) external onlyRole(ADMIN_ROLE) {
        require(_token != ETH_ADDRESS && _token != address(0), "Token invalido");
        require(_feed != address(0), "Feed requerido");
        require(_limiteTransaccion > 0, "Limite debe ser > 0");
        if (s_tokensRegistrados[_token]) revert KipuBankV2_TokenYaRegistrado();
        
        AggregatorV3Interface feed = AggregatorV3Interface(_feed);
        uint8 feedDecimals = feed.decimals();
        
        // Auto-detectar decimals del token si se pasa 0
        uint8 tokenDecimals = _decimals;
        if (_decimals == 0) {
            try IERC20Metadata(_token).decimals() returns (uint8 dec) {
                tokenDecimals = dec;
            } catch {
                tokenDecimals = feedDecimals;
            }
        }
        
        s_tokensRegistrados[_token] = true;
        s_tokenFeeds[_token] = _feed;
        s_tokenDecimals[_token] = tokenDecimals;
        s_limitesPorToken[_token] = _limiteTransaccion;
        s_tokenList.push(_token);
        
        emit TokenRegistrado(_token, _feed, tokenDecimals, _limiteTransaccion);
    }

    function actualizarLimiteToken(address _token, uint256 _nuevoLimite) external onlyRole(ADMIN_ROLE) {
        require(s_tokensRegistrados[_token] || _token == ETH_ADDRESS, "Token no registrado");
        require(_nuevoLimite > 0, "Limite debe ser > 0");
        s_limitesPorToken[_token] = _nuevoLimite;
        emit LimiteTokenActualizado(_token, _nuevoLimite);
    }

    function actualizarFeedToken(address _token, address _nuevoFeed) external onlyRole(ADMIN_ROLE) {
        require(s_tokensRegistrados[_token] || _token == ETH_ADDRESS, "Token no registrado");
        require(_nuevoFeed != address(0), "Feed invalido");
        s_tokenFeeds[_token] = _nuevoFeed;
        emit FeedTokenActualizado(_token, _nuevoFeed);
    }

    // ====================
    // ===== DEPÓSITOS ====
    // ====================
    function depositarETH() external payable 
        montoMayorQueCero(msg.value) 
        nonReentrant
    {
        _procesarDeposito(ETH_ADDRESS, msg.value, msg.sender);
    }

    function depositarERC20(address _token, uint256 _monto) external 
        montoMayorQueCero(_monto)
        nonReentrant
        soloTokenRegistrado(_token)
    {
        _procesarDeposito(_token, _monto, msg.sender);
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _monto);
    }

    // ====================
    // ===== RETIROS ======
    // ====================
    function retirarETH(uint256 _monto) external 
        montoMayorQueCero(_monto)
        nonReentrant
    {
        _procesarRetiro(ETH_ADDRESS, _monto, msg.sender);
        (bool success, ) = msg.sender.call{value: _monto}("");
        if (!success) revert KipuBankV2_TransferenciaFallida();
    }

    function retirarERC20(address _token, uint256 _monto) external 
        montoMayorQueCero(_monto)
        nonReentrant
        soloTokenRegistrado(_token)
    {
        _procesarRetiro(_token, _monto, msg.sender);
        IERC20(_token).safeTransfer(msg.sender, _monto);
    }

    // ====================
    // ===== FUNCIONES INTERNAS
    // ====================
    function _procesarDeposito(address _token, uint256 _monto, address _usuario) private {
        if (_monto > s_limitesPorToken[_token]) {
            revert KipuBankV2_MontoMayorAlLimite();
        }

        uint256 valorUSD = _convertirAUSD(_token, _monto);
        uint256 nuevoTotalUSD = calcularTotalBalanceUSD() + valorUSD;
        
        if (nuevoTotalUSD > i_limiteGlobalUSD) {
            revert KipuBankV2_BancoSinCapacidad();
        }

        s_balances[_token][_usuario] += _monto;
        s_totalBalances[_token] += _monto;
        s_totalDepositos++;

        emit Deposito(_token, _usuario, _monto, valorUSD);
    }

    function _procesarRetiro(address _token, uint256 _monto, address _usuario) private {
        if (s_balances[_token][_usuario] < _monto) {
            revert KipuBankV2_SaldoInsuficiente();
        }

        if (_monto > s_limitesPorToken[_token]) {
            revert KipuBankV2_MontoMayorAlLimite();
        }

        s_balances[_token][_usuario] -= _monto;
        s_totalBalances[_token] -= _monto;
        s_totalRetiros++;

        uint256 valorUSD = _convertirAUSD(_token, _monto);
        emit Retiro(_token, _usuario, _monto, valorUSD);
    }

    function _convertirAUSD(address _token, uint256 _monto) private view returns (uint256) {
        address feedAddress = s_tokenFeeds[_token];
        if (feedAddress == address(0)) revert KipuBankV2_FeedNoConfigurado();
        
        AggregatorV3Interface feed = AggregatorV3Interface(feedAddress);
        (, int256 price, , , ) = feed.latestRoundData();
        if (price <= 0) revert KipuBankV2_PrecioInvalido();
        
        uint8 tokenDecimals = s_tokenDecimals[_token];
        uint8 feedDecimals = feed.decimals();
        uint256 priceUint = uint256(price);
        
        // Fórmula generalizada y más precisa
        uint256 numerator = _monto * priceUint * (10 ** INTERNAL_DECIMALS);
        uint256 denominator = 10 ** (tokenDecimals + feedDecimals);
        
        return numerator / denominator;
    }

    // ====================
    // ===== CONSULTAS =====
    // ====================
    function saldoDe(address _token, address _usuario) external view returns (uint256) {
        return s_balances[_token][_usuario];
    }

    function saldoDeUSD(address _token, address _usuario) external view returns (uint256) {
        return _convertirAUSD(_token, s_balances[_token][_usuario]);
    }

    function calcularTotalBalanceUSD() public view returns (uint256 totalUSD) {
        if (s_tokenList.length > MAX_ITERATIONS) revert KipuBankV2_IteracionDemasiadoGrande();
        
        for (uint256 i = 0; i < s_tokenList.length; ) {
            address token = s_tokenList[i];
            if (s_totalBalances[token] > 0) {
                totalUSD += _convertirAUSD(token, s_totalBalances[token]);
            }
            unchecked { i++; }
        }
        return totalUSD;
    }

    function obtenerLimiteToken(address _token) external view returns (uint256) {
        return s_limitesPorToken[_token];
    }

    function convertirAUSD(address _token, uint256 _monto) external view returns (uint256) {
        return _convertirAUSD(_token, _monto);
    }

    function obtenerTokensRegistrados() external view returns (address[] memory) {
        return s_tokenList;
    }

    function capacidadDisponibleUSD() external view returns (uint256) {
        uint256 totalActual = calcularTotalBalanceUSD();
        return totalActual >= i_limiteGlobalUSD ? 0 : i_limiteGlobalUSD - totalActual;
    }

    // ====================
    // ===== RECEIVE/FALLBACK
    // ====================
    receive() external payable {
        if (msg.value > 0) {
            _procesarDeposito(ETH_ADDRESS, msg.value, msg.sender);
            emit RecepcionETH(msg.sender, msg.value);
        }
    }

    fallback() external payable {
        if (msg.value > 0) {
            revert KipuBankV2_TransaccionNoPermitida();
        }
        revert KipuBankV2_TransaccionNoPermitida();
    }

    // ====================
    // ===== EMERGENCY ====
    // ====================
    function retiroEmergencia(address _token, address _destino) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(_destino != address(0), "Destino invalido");
        uint256 balance;
        
        if (_token == ETH_ADDRESS) {
            balance = address(this).balance;
            (bool success, ) = _destino.call{value: balance}("");
            require(success, "Transferencia ETH fallida");
        } else {
            balance = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(_destino, balance);
        }
    }
}

