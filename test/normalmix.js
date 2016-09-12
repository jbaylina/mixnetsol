/*jslint node: true */
/*global describe, it, before, beforeEach, after, afterEach */
"use strict";



var mixNetHelper = require('../mixnet_helper.js');
var ethConnector = require('ethconnector');
var ethUtil = require('ethereumjs-util');
var Wallet = require('ethereumjs-wallet');
var MixUser = require('../mixuser.js');
var BigNumber = require('bignumber.js');
var xor = require('../xor_bignumber.js');


var assert = require("assert"); // node.js core module
var async = require('async');
var _ = require('lodash');

var verbose = false;
var NUsers = 3;
var depositValue = 10;  // In Ethers

function log(S) {
    if (verbose) {
        console.log(S);
    }
}

function send(method, params, callback) {
    if (typeof params == "function") {
      callback = params;
      params = [];
    }

    ethConnector.web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: method,
      params: params || [],
      id: new Date().getTime()
    }, callback);
}



describe('Normal MixNet Operation', function(){
    var mixNet;
    var accounts;
    var mixUsers;
    var seed;
    var users = [];
    before(function(done) {
        ethConnector.init('testrpc',done);
    });
    it('should deploy the MixNet ', function(done){
        this.timeout(200000000);
        mixNetHelper.deploy({}, function(err, _mixNet) {
            assert.ifError(err);
            assert.ok(_mixNet.address);
            mixNet = _mixNet;
            done();
        });
    });
    it('Should have the correct ec address', function(done) {
        mixNet.getECAddress(function(err, addr) {
            log(addr);
            done();
        });
    });
    it('Should get accounts', function(done) {
        ethConnector.web3.eth.getAccounts(function(err, _accounts) {
            assert.ifError(err);
            accounts = _accounts;
            assert(accounts.length>NUsers, "Too low users");
            done();
        });
    });
    it('Should create NUsers wallets and deposit', function(done) {
        mixUsers = new Array(NUsers);
        var i=0;
        async.whilst(
            function() { return i < NUsers; },
            function(cb) {
                var dest = '0x'+Wallet.generate().getAddress().toString('hex');
                mixUsers[i] = new MixUser(dest);
                mixNet.deposit(
                    mixUsers[i].getPubX(),
                    mixUsers[i].getPubY(),
                    {
                        from: accounts[i],
                        value: ethConnector.web3.toWei(depositValue),
                        gas: 3000000
                    }, function(err) {
                        if(err) return cb(err);
                        cb();
                    }
                );
                i++;
            },
            function (err, n) {
                assert.ifError(err);
                done();
            }
        );
    });
    it('Should close', function(done) {
        mixNet.close({from: accounts[0], gas: 200000}, function(err) {
            assert.ifError(err);
            mixNet.getState(function(err, _st) {
                assert.ifError(err);
                assert.equal(_st, 1);
                send("evm_mine", function(err, result) {
                    assert.ifError(err);
                    done();
                });
            });
        });
    });
    it('Get users list', function(done) {
        mixNet.getNUsers(function(err, _NUsers) {
            assert.ifError(err);
            assert.equal(_NUsers, NUsers);
            var i=0;
            async.whilst(
                function() { return i < NUsers; },
                function(cb) {
                    mixNet.getUserPubKey(
                        i, function(err, res) {
                            if(err) return cb(err);
                            assert.equal(res[0].toString(16), mixUsers[i].getPubX().toString(16));
                            assert.equal(res[1].toString(16), mixUsers[i].getPubY().toString(16));
                            users.push({
                                pubX: res[0],
                                pubY: res[1]
                            });
                            i++;
                            cb();
                        }
                    );
                },
                function (err, n) {
                    assert.ifError(err);
                    done();
                }
            );
        });
    });
    it('Should get seed', function(done) {
        mixNet.getSeed(function(err, _seed) {
            assert.ifError(err);
            log("Seed: " + _seed.toString(16));
            assert(!_seed.isZero());
            seed = _seed;
            done();
        });
    });
    it('Should send hash', function(done) {
        log("Start sendHash");
        async.eachSeries( _.range(0,NUsers),
            function(i, cb) {
                log("start User " + i);
                mixUsers[i].calculateMix(users,seed);
                log("Hash "+i+": "+mixUsers[i].getHash());
                log("Account " +i +": " +accounts[i]);
                mixNet.setHash(
                    mixUsers[i].getHash(),
                    {
                        from: accounts[i],
                        gas: 2000000
                    },
                    function(err, res) {
                        if(err) return cb(err);
                        cb();
                    }
                );
            },
            function (err) {
                assert.ifError(err);
                mixNet.getState(function(err, _st) {
                    assert.ifError(err);
                    assert.equal(_st, 2);
                    log("hashed");
                    done();
                });
            }
        );
    });
    it('Should mix', function(done) {
        async.eachSeries( _.range(0,NUsers),
            function(i,cb) {
                log("start mix User " + i);
                mixNet.mix(
                    mixUsers[i].getData(),
                    {
                        from: accounts[i],
                        gas: 4700000
                    },
                    function(err, res) {
                        if(err) return cb(err);
                        i++;
                        cb();
                    }
                );
            },
            function (err, n) {
                assert.ifError(err);
                done();
/*                mixNet.debug(function(err,res) {
                    assert.ifError(err);
                    log("st1: " + res[0]);
                    log("st2: " + res[1].toString(16));
                    mixNet.getState(function(err, _st) {
                        assert.ifError(err);
                        log("After Mix State: " + _st);
                        printBoardCalc();
                        printBoard(done);
                    });
                }); */
            }
        );
    });
    it('Should match result', function(done) {
        var i=0;
        async.whilst(
            function() { return i < NUsers; },
            function(cb) {
                ethConnector.web3.eth.getBalance(mixUsers[i].dest, function(err, b) {
                    if(err) return cb(err);
                    log(mixUsers[i].dest + ": " + ethConnector.web3.toWei(depositValue).toString(10) );
                    assert.equal(b.toString(10), ethConnector.web3.toWei(depositValue).toString(10) );
                    i++;
                    cb();
                });
            },
            function (err, n) {
                assert.ifError(err);
                done();
            }
        );
    });
    it("If should disacpear contract", function(done) {
        ethConnector.web3.eth.getCode(mixNet.address, function(err, code) {
            assert.ifError(err);
            log(code);
            assert(code.length, 3);
            done();
        });
    });

    function printBoard(cb) {
        log("result board");
        async.eachSeries( _.range(0,NUsers*5*2), function(i, cb) {
            mixNet.getBoard(i, function(err,d) {
                if (err) return cb(err);
                log(d);
                cb();
            });
        }, cb);
    }

    function printBoardCalc() {
        log("calc board");
        var NSlots = NUsers*5*2;
        var board = new Array(NSlots);
        var i,j;
        for (j=0; j<NSlots; j++) board[j] = new BigNumber(0);
        for (i=0; i<NUsers; i++) {
            for (j=0; j<NSlots; j++) board[j] = xor(board[j], mixUsers[i].mixData[j]);
        }
        for (j=0; j<NSlots; j++) {
            var n = board[j].toString(16);
            while (n.length < 64) n= '0'+n;
            log("0x"+n);
        }
    }
});
