pragma solidity 0.5.8;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";

/// @title Let two accounts play a 1/3/5-round Rock, Paper & Scissors game against each other
/// @notice B9lab Blockstars Certified Ethereum Developer Course
/// @notice Module 9 project: Rock, Paper & Scissors
/// @author Fábio Corrêa <feamcor@gmail.com>
/// @dev Rules taken from `https://en.wikipedia.org/wiki/Rock%E2%80%93paper%E2%80%93scissors`
contract RockPaperScissors is Pausable {
    using SafeMath for uint;

    enum Hand {
        UNSET, // 0
        ROCK, // 1
        PAPER, // 2
        SCISSORS, // 3
        UNKNOWN // 4
    }

    enum Who {
        NOBODY, // 0
        PLAYER, // 1
        OPPONENT, // 2
        VALIDATOR // 3
    }

    enum Result {
        DRAW, // 0
        PLAYER, // 1
        OPPONENT // 2
    }

    struct Game {
        uint bet;
        uint roundsLeft;
        uint won;
        bytes32 secretHand;
        uint deadline;
        address opponent;
        uint opponentBet;
        uint opponentWon;
        Hand opponentHand;
        Who turn;
    }

    // Balance in wei of an account (key) held by the contract.
    mapping(address => uint) public balances;

    // Track of games led by players (key).
    mapping(address => Game) public games;

    event Started(
        address indexed player,
        uint bet,
        uint roundsLeft,
        bytes32 secretHand,
        uint deadline,
        address indexed opponent
    );

    event OpponentStarted(
        address indexed opponent,
        uint bet,
        Hand hand,
        uint deadline,
        address indexed player
    );

    event Played(
        address indexed player,
        bytes32 secretHand,
        uint deadline
    );

    event OpponentPlayed(
        address indexed opponent,
        Hand hand,
        uint deadline,
        address indexed player
    );

    event RoundChecked(
        address indexed player,
        bytes32 secret,
        Hand hand,
        uint deadline,
        Result result,
        address indexed opponent
    );

    event Finished(
        address indexed player,
        address indexed opponent,
        uint total,
        uint won,
        uint opponentWon
    );

    event Cancelled(
        address indexed by,
        address indexed player,
        uint bet,
        address indexed opponent,
        uint opponentBet
    );

    event Withdrew(
        address indexed by,
        uint balance
    );


    function start(address _opponent, bytes32 _secretHand, uint _rounds)
        external
        payable
        whenNotPaused
    {
        startHelper(_opponent, _secretHand, _rounds, msg.value);
    }

    function startFromBalance(address _opponent, bytes32 _secretHand, uint _rounds)
        external
        whenNotPaused
    {
        uint _balance = balances[msg.sender];
        emit Withdrew(msg.sender, _balance);
        balances[msg.sender] = uint(0);
        startHelper(_opponent, _secretHand, _rounds, _balance);
    }

    function opponentStart(address _player, Hand _hand)
        external
        payable
        whenNotPaused
    {
        opponentStartHelper(_player, _hand, msg.value);
    }

    function opponentStartFromBalance(address _player, Hand _hand)
        external
        whenNotPaused
    {
        uint _balance = balances[msg.sender];
        emit Withdrew(msg.sender, _balance);
        balances[msg.sender] = uint(0);
        opponentStartHelper(_player, _hand, _balance);
    }

    function play(bytes32 _secretHand) external whenNotPaused {
        require(_secretHand != bytes32(0), "invalid secret hand");
        Game storage _game = games[msg.sender];
        require(_game.opponent != address(0x0), "game not started");
        require(_game.roundsLeft != uint(0), "no rounds left");
        require(_game.turn == Who.PLAYER, "not your turn");

        // solium-disable-next-line security/no-block-members
        _game.deadline = block.timestamp.add(3600 + 15);
        _game.secretHand = _secretHand;
        _game.turn = Who.OPPONENT;

        emit Played(msg.sender, _secretHand, _game.deadline);
    }

    function opponentPlay(address _player, Hand _hand) external whenNotPaused {
        require(_hand > Hand.UNSET && _hand < Hand.UNKNOWN, "invalid hand");
        Game storage _game = games[_player];
        require(_game.opponent == msg.sender, "invalid opponent");
        require(_game.roundsLeft != uint(0), "no rounds left");
        require(_game.turn == Who.OPPONENT, "not your turn");

        // solium-disable-next-line security/no-block-members
        _game.deadline = block.timestamp.add(3600 + 15);
        _game.opponentHand = Hand(_hand);
        _game.turn = Who.VALIDATOR;

        emit OpponentPlayed(msg.sender, _hand, _game.deadline, _player);
    }

    function check(bytes32 _secret, Hand _hand)
        external
        whenNotPaused
        returns (Result _result)
    {
        require(_secret != bytes32(0), "invalid secret");
        require(_hand > Hand.UNSET && _hand < Hand.UNKNOWN, "invalid hand");
        Game storage _game = games[msg.sender];
        require(_game.opponent != address(0x0), "game not started");
        require(_game.turn == Who.VALIDATOR, "not your turn");
        bytes32 _secretHand = generateSecretHand(address(this), msg.sender, _game.opponent, _secret, _hand);
        require(_game.secretHand == _secretHand, "secret/hand mismatch");

        if(_hand != _game.opponentHand) {
            if(_hand == Hand.ROCK) {
                if(_game.opponentHand == Hand.SCISSORS) {
                    _result = Result.PLAYER; // rock crushes scissors
                } else if(_game.opponentHand == Hand.PAPER) {
                    _result = Result.OPPONENT; // paper covers rocks
                }
            } else if(_hand == Hand.PAPER) {
                if(_game.opponentHand == Hand.ROCK) {
                    _result = Result.PLAYER; // paper covers rocks
                } else if(_game.opponentHand == Hand.SCISSORS) {
                    _result = Result.OPPONENT; // scissors cuts papers
                }
            } else { // _hand == Hard.SCISSORS
                if(_game.opponentHand == Hand.ROCK) {
                    _result = Result.OPPONENT; // rock crushes scissors
                } else if(_game.opponentHand == Hand.PAPER) {
                    _result = Result.PLAYER; // scissors cuts papers
                }
            }
        } // otherwise it is a draw

        if(_result != Result.DRAW) {
            _game.roundsLeft = _game.roundsLeft.sub(1);
            if(_result == Result.PLAYER) {
                _game.won = _game.won.add(1);
            } else { // _result == Result.OPPONENT
                _game.opponentWon = _game.opponentWon.add(1);
            }
        }

        // solium-disable-next-line security/no-block-members
        _game.deadline = block.timestamp.add(3600 + 15);
        _game.turn = Who.PLAYER;
        emit RoundChecked(msg.sender, _secret, _hand, _game.deadline, _result, _game.opponent);

        if(_game.roundsLeft == uint(0) ||
            _game.won > _game.roundsLeft ||
            _game.opponentWon > _game.roundsLeft)
        {
            uint _totalBet = _game.bet.add(_game.opponentBet);
            emit Finished(msg.sender, _game.opponent, _totalBet, _game.won, _game.opponentWon);
            if(_game.won > _game.opponentWon) {
                balances[msg.sender] = balances[msg.sender].add(_totalBet);
            } else {
                balances[_game.opponent] = balances[_game.opponent].add(_totalBet);
            }
            releaseGame(msg.sender);
        }
    }

    function cancel(address _player, address _opponent) external whenNotPaused
    {
        require(msg.sender == _player || msg.sender == _opponent, "address mismatch");
        Game storage _game = games[_player];
        require(_game.opponent == _opponent, "invalid opponent");
        // solium-disable-next-line security/no-block-members
        require(block.timestamp > _game.deadline, "too early to cancel");
        balances[_player] = balances[_player].add(_game.bet);
        balances[_opponent] = balances[_opponent].add(_game.opponentBet);
        emit Cancelled(msg.sender, _player, _game.bet, _opponent, _game.opponentBet);
        releaseGame(_player);
    }

    function withdraw() external whenNotPaused
    {
        uint _balance = balances[msg.sender];
        require(_balance != uint(0), "no balance available");
        balances[msg.sender] = uint(0);
        emit Withdrew(msg.sender, _balance);
        msg.sender.transfer(_balance);
    }

    function generateSecretHand(
        address _contract,
        address _player,
        address _opponent,
        bytes32 _secret,
        Hand _hand)
        public
        pure
        returns (bytes32)
    {
        require(_contract != address(0x0), "invalid contract");
        require(_player != address(0x0), "invalid player");
        require(_opponent != address(0x0), "invalid opponent");
        require(_hand > Hand.UNSET && _hand < Hand.UNKNOWN, "invalid hand");
        return keccak256(abi.encodePacked(_contract, _player, _opponent, _secret, _hand));
    }

    function releaseGame(address _player) private {
        Game storage _game = games[_player];
        _game.bet = uint(0);
        _game.roundsLeft = uint(0);
        _game.won = uint(0);
        _game.secretHand = bytes32(0);
        _game.deadline = uint(0);
        _game.opponent = address(0x0);
        _game.opponentBet = uint(0);
        _game.opponentWon = uint(0);
        _game.opponentHand = Hand.UNSET;
        _game.turn = Who.NOBODY;
    }

    function startHelper(
        address _opponent,
        bytes32 _secretHand,
        uint _rounds,
        uint _bet)
        private
    {
        require(_opponent != address(0x0), "invalid opponent");
        require(_secretHand != bytes32(0), "invalid secret hand");
        require(_rounds == uint(1) || _rounds == uint(3) || _rounds == uint(5), "invalid rounds");
        require(games[msg.sender].opponent == address(0x0), "game in progress");

        Game memory _game = Game({
            bet: _bet,
            roundsLeft: _rounds,
            won: uint(0),
            secretHand: _secretHand,
            // deadline is now plus 1 hour and 15s (block average time)
            // solium-disable-next-line security/no-block-members
            deadline: block.timestamp.add(3600 + 15),
            opponent: msg.sender,
            opponentBet: uint(0),
            opponentWon: uint(0),
            opponentHand: Hand.UNSET,
            turn: Who.OPPONENT
        });

        games[msg.sender] = _game;

        emit Started(
            msg.sender,
            _game.bet,
            _game.roundsLeft,
            _game.secretHand,
            _game.deadline,
            _game.opponent);
    }

    function opponentStartHelper(
        address _player,
        Hand _hand,
        uint _bet)
        private
    {
        require(_hand > Hand.UNSET && _hand < Hand.UNKNOWN, "invalid hand");
        Game storage _game = games[_player];
        require(msg.sender == _game.opponent, "invalid game");
        require(_bet >= _game.bet, "bet too low");
        require(_game.opponentHand == Hand.UNSET, "game already started");
        require(_game.turn == Who.OPPONENT, "not your turn");

        // solium-disable-next-line security/no-block-members
        _game.deadline = block.timestamp.add(3600 + 15);
        _game.roundsLeft = _game.roundsLeft.sub(1);
        _game.opponentBet = _bet;
        _game.opponentHand = Hand(_hand);
        _game.turn = Who.VALIDATOR;

        emit OpponentStarted(
            msg.sender,
            msg.value,
            _hand,
            _game.deadline,
            _player);
    }
}