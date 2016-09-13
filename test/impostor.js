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
var NSlotsPerUser = 5;
var depositValue = 10;  // In Ethers
var fee = 1;

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



describe('One impostor change the data', function(){
    var mixNet;
    var accounts;
    var mixUsers;
    var seed;
    var users = [];
    before(function(done) {
        ethConnector.init('testrpc',done);
    });
    it('should deploy a mixNet ', function(done){
        this.timeout(200000000);
        mixNetHelper.deploy({
            depositValue: ethConnector.web3.toWei(depositValue),
            fee: ethConnector.web3.toWei(fee),
            maxUsers: 5
        }, function(err, _mixNet) {
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
        this.timeout(200000000);
        log("Creating user wallets and epositing" + NUsers);
        mixUsers = new Array(NUsers);
        async.eachSeries( _.range(0,NUsers),
            function(i, cb) {
                var dest = '0x'+Wallet.generate().getAddress().toString('hex');
                mixUsers[i] = new MixUser(dest);
                log("hashRand: " + mixUsers[i].getHashRnd());
                mixNet.deposit(
                    mixUsers[i].getPubX(),
                    mixUsers[i].getPubY(),
                    mixUsers[i].getHashRnd(),
                    {
                        from: accounts[i],
                        value: ethConnector.web3.toWei(depositValue),
                        gas: 3000000
                    }, function(err) {
                        if(err) return cb(err);
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
    it('Should close', function(done) {
        bcDelay(3600+10, function(err) {
            assert.ifError(err);
            mixNet.getState(function(err, _st) {
                assert.ifError(err);
                assert.equal(_st.toNumber(), 1);
                done();
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
    it('Should generateSeed', function(done) {
        log("Start generateSeed");
        async.eachSeries( _.range(0,NUsers),
            function(i, cb) {
                log("start User " + i);
                mixNet.setRnd(
                    mixUsers[i].getRnd(),
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
                    log("Random generated");
                    done();
                });
            }
        );
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

                // The shame
                if (i==1) {
                    mixUsers[i].mixData[mixUsers[i].mixData.length-1] =
                        xor(  mixUsers[i].mixData[mixUsers[i].mixData.length-1],
                            new BigNumber('aaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbb',16));
                    mixUsers[i].mixDataHash = recalcHash(mixUsers[i].mixData);
                }
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
                    assert.equal(_st, 3);
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
            }
        );
    });
    it('Should be in validation state', function(done) {
        mixNet.getState(function(err, _st) {
            assert.ifError(err);
            assert.equal(_st, 4);
            done();
        });
    });
    it('Should check data', function(done) {
        mixNet.calcDataHash(mixUsers[0].getPrivate(),seed,mixUsers[0].dest,function(err, res) {
            assert.ifError(err);
            var cData = res;
            log ('Contract Data: 0x'+cData.toString(16));
            var lData = mixUsers[0].calcDataHash();
            log ('Local Data: 0x'+lData.toString(16));
            assert(lData.equals(cData));
            done();
        });
    });
    it('Should validate and receive back the Ether', function(done) {
        this.timeout(2000000);
        var initalBalance;
        async.series([
            function(cb) {
                ethConnector.web3.eth.getBalance(accounts[0], function(err, b) {
                    if(err) return cb(err);
                    initalBalance = ethConnector.web3.fromWei(b).toNumber();
                    log("initalBalance: " + initalBalance );
                    cb();
                });
            },
            function(cb) {
                async.eachSeries( _.range(0,NUsers+1),
                    function(i, cb) {
                        mixNet.validate(
                            mixUsers[0].getPrivate(),
                            mixUsers[0].dest,
                            {
                                from: accounts[0],
                                gas: 2000000
                            }, function(err) {
                                if(err) return cb(err);
                                mixNet.userStates(0, function(err, res) {
                                    log(JSON.stringify(res));
                                    assert.equal(res[8].toNumber(), i+1);
                                    assert.equal(res[9], i == NUsers ? true: false);
                                    cb();
                                });
                            });
                    },
                    cb
                );
            },
            function(cb) {
                mixNet.getSeed(function(err, _seed) {
                    assert.ifError(err);
                    log("Seed2: " + _seed.toString(16));
                    assert(!_seed.isZero());
                    seed = _seed;
                    cb();
                });
            },
            function(cb) {
                printMaskC(0, function(err) {
                    if(err) return cb(err);
                    printMaskL(0);
                    cb();
                });
            },
            function(cb) {
                ethConnector.web3.eth.getBalance(accounts[0], function(err, b) {
                    if(err) return cb(err);
                    var finalBalance = ethConnector.web3.fromWei(b).toNumber();
                    log("finalBalance: " + finalBalance );
                    var diff = finalBalance -initalBalance;
                    log("Diff: " + diff );
                    assert(diff > 9);
                    cb();
                });
            }
        ], done);
    });
    it('Should wait unitil terminate', function(done) {
        bcDelay(3600+10, function(err) {
            if (err) return done(err);
            mixNet.getState(function(err, _st) {
                assert.ifError(err);
                log("In terminate phase");
                assert.equal(_st, 5);
                done();
            });
        });
    });
    it('Should recover others fee', function(done) {
        this.timeout(2000000);
        async.eachSeries( _.range(0,NUsers),
            function(i,cb) {
                var initalBalance;
                log("start terminate User " + i);
                async.series([
                    function(cb) {
                        ethConnector.web3.eth.getBalance(accounts[i], function(err, b) {
                            if(err) return cb(err);
                            initalBalance = ethConnector.web3.fromWei(b).toNumber();
                            log("initalBalance "+i+": " + initalBalance );
                            cb();
                        });
                    },
                    function(cb) {
                        mixNet.terminate(
                            {
                                from: accounts[i],
                                gas: 4700000
                            },
                            function(err, res) {
                                if(err) return cb(err);
                                cb();
                            }
                        );
                    },
                    function(cb) {
                        ethConnector.web3.eth.getBalance(accounts[i], function(err, b) {
                            if(err) return cb(err);
                            var finalBalance = ethConnector.web3.fromWei(b).toNumber();
                            log("finalBalance "+i+": " + finalBalance );
                            var diff = finalBalance - initalBalance;
                            log("diff " + i +": " + finalBalance );
                            if (i===0) {
                                assert(diff>1.9);
                                assert(diff<2);
                            } else {
                                assert(diff>8.9);
                                assert(diff<9);
                            }
                            cb();
                        });
                    }
                ], cb);
            },
            function (err, n) {
                assert.ifError(err);
                done();
            }
        );
    });
    it("If should disapear contract", function(done) {
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
        var NSlots = NUsers*NSlotsPerUser*2;
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

    function printMaskC(idx, cb) {
        log("result Mask Contract" + idx);
        async.eachSeries( _.range(0,NUsers*NSlotsPerUser*2), function(i, cb) {
            mixNet.getMask(idx, i, function(err,d) {
                if (err) return cb(err);
                log(d);
                cb();
            });
        }, cb);
    }

    function printMaskL(idx) {
        log("result Mask Local" + idx);
        var j;
        var len = NUsers * NSlotsPerUser * 2;
        for (j=0; j<len; j++) {
            var n = mixUsers[idx].mixData[j].toString(16);
            while (n.length < 64) n= '0'+n;
            log("0x"+n);
        }
    }

    function recalcHash(data) {
        var i;
        var maskH = "";
        for (i=0; i<data.length; i++) {
            var aux = data[i].toString(16);
            while (aux.length < 64) aux = '0' + aux;
            maskH = maskH + aux;
        }

        var res = ethConnector.web3.sha3( maskH,  {encoding: 'hex'});
        return res;
    }

    function bcDelay(secs, cb) {
        send("evm_increaseTime", [secs], function(err, result) {
            if (err) return cb(err);

      // Mine a block so new time is recorded.
            send("evm_mine", function(err, result) {
                if (err) return cb(err);
                cb();
            });
        });
    }
});
