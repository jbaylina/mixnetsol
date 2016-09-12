/*jslint node: true */
"use strict";

var async = require('async');
var ethConnector = require('ethconnector');
var path = require('path');
var ecHelper = require('ecsol');

exports.deploy = function(opts, cb) {
    var compilationResult;
    return async.waterfall([
        function(cb) {
            ecHelper.deploy({},function(err, ec) {
                if (err) return cb(err);
                opts.ECAddress = ec.address;
                cb();
            });
        },
        function(cb) {
            ethConnector.loadSol(path.join(__dirname, "mixnet.sol"), cb);
        },
        function(src, cb) {
            ethConnector.applyConstants(src, opts, cb);
        },
        function(src, cb) {
            ethConnector.compile(src, cb);
        },
        function(result, cb) {
            compilationResult = result;
            ethConnector.deploy(compilationResult.MixNet.interface,
                compilationResult.MixNet.bytecode,
                0,
                0,
                opts.depositValue,
                opts.fee,
                opts.maxUsers,
                cb);
        },
    ], function(err, mixnet) {
        if (err) return cb(err);
        cb(null,mixnet, compilationResult);
    });
};
