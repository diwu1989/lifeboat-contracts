// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./IStdReference.sol";
import "./ISwappaRouterV1.sol";
import "./IERC20.sol";
import "./SafeDecimalMath.sol";
import "./SafeMath.sol";

contract Lifeboat {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    // Swappa router to use for completing the swap
    ISwappaRouterV1 public immutable swappa;
    // Oracle for reference price
    IStdReference public immutable oracle;
    // Limit for max swap amount per user
    uint256 public immutable limit;
    // Source token for the swap
    IERC20 public immutable source;
    // Destination token for the swap
    IERC20 public immutable destination;
    // Gas depot to pay for rescue transactions
    address payable public immutable gasDepot;
    // Oracle base token
    string public oracleBase;
    // Oracle quote token
    string public oracleQuote;

    // Swapped balance for each user
    mapping(address => State) public states;

    struct State {
        // Amount of remaining tokens to swap
        uint256 remaining;
        // Depeg threshold to trigger the swap as a decimal
        // e.g. 0.95 CUSD/USD
        uint256 depegThreshold;
        // Minimum price to accept for the swap as a decimal
        // e.g. 0.90 USDC/CUSD (source / destination)
        uint256 minimumPrice;
    }

    struct SwapArgs {
        address[] path;
        address[] pairs;
        bytes[] extras;
        uint256 deadline;
    }

    event StateChanged(address indexed user, State state);

    constructor(
        ISwappaRouterV1 _swappa,
        IStdReference _oracle,
        uint256 _limit,
        IERC20 _source,
        IERC20 _destination,
        address payable _gasDepot,
        string memory _oracleBase,
        string memory _oracleQuote
    ) {
        swappa = _swappa;
        oracle = _oracle;
        limit = _limit;
        source = _source;
        destination = _destination;
        gasDepot = _gasDepot;
        oracleBase = _oracleBase;
        oracleQuote = _oracleQuote;

        // sanity check that the oracle reference data is correct
        require(getCurrentPeg() > 0, "invalid oracle reference data");
        // sanity check the source and destination tokens
        require(source.totalSupply() > 0, "invalid source token");
        require(destination.totalSupply() > 0, "invalid destination token");
        // sanity check the limit
        require(limit > 0, "invalid limit");
    }

    function getCurrentPeg() public view returns (uint256) {
        return oracle.getReferenceData(oracleBase, oracleQuote).rate;
    }

    function unenroll() public {
        delete states[msg.sender];
        emit StateChanged(msg.sender, states[msg.sender]);
    }

    function enroll(
        uint256 amount,
        uint256 depegThreshold,
        uint256 minimumPrice
    ) public payable returns (State memory state) {
        if (amount == 0) {
            // enrolling with amount 0 is the same as unenrolling
            unenroll();
            return state;
        }

        // do not allow enrollment greater than contract limit
        state.remaining = amount > limit ? limit : amount;
        state.depegThreshold = depegThreshold;
        state.minimumPrice = minimumPrice;

        require(msg.value > 0, "missing gas depot donation");
        require(
            0 < depegThreshold && depegThreshold < SafeDecimalMath.UNIT,
            "invalid depeg threshold"
        );
        require(
            0 < minimumPrice && minimumPrice < depegThreshold,
            "invalid minimum price"
        );

        gasDepot.transfer(address(this).balance);
        states[msg.sender] = state;
        emit StateChanged(msg.sender, state);
        return state;
    }

    function effectiveRemaining(address user) public view returns (uint256) {
        uint256 remaining = states[user].remaining;
        uint256 allowance = source.allowance(user, address(this));
        if (allowance < remaining) {
            // allowance is not enough
            remaining = allowance;
        }
        uint256 balance = source.balanceOf(user);
        if (balance < remaining) {
            // balance is not enough
            remaining = balance;
        }
        return remaining;
    }

    function swap(address user, SwapArgs calldata args)
        public
        returns (uint256 outputAmount)
    {
        State memory state = states[user];
        require(getCurrentPeg() < state.depegThreshold, "current peg safe");
        require(
            args.path[0] == address(source) &&
                args.path[args.path.length - 1] == address(destination),
            "invalid swap path"
        );

        uint256 inputAmount = effectiveRemaining(user);
        require(inputAmount > 0, "invalid input amount");

        // use the minimal price to rescale to the destination token
        uint256 minOutputAmount = inputAmount
            .multiplyDecimal(state.minimumPrice)
            .mul(destination.decimals())
            .div(source.decimals());

        // pull the necessary input amount from the user
        require(
            source.transferFrom(user, address(this), inputAmount),
            "failed to transfer input"
        );
        require(
            source.approve(address(swappa), inputAmount),
            "failed to approve swappa"
        );
        outputAmount = swappa.swapExactInputForOutputWithPrecheck(
            args.path,
            args.pairs,
            args.extras,
            inputAmount,
            minOutputAmount,
            user,
            args.deadline
        );

        // decrement the remaining and emit
        uint256 remaining = state.remaining.sub(inputAmount);
        if (remaining == 0) {
            delete states[user];
        } else {
            states[user].remaining = remaining;
        }
        emit StateChanged(user, states[user]);
        return outputAmount;
    }

    function rescueERC20(IERC20 token) external returns (bool) {
        return token.transfer(gasDepot, token.balanceOf(address(this)));
    }
}
