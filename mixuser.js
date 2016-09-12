/*jslint node: true */
"use strict";


var ethConnector = require('ethconnector');
var BigNumber = require('bignumber.js');
var EC = require('elliptic').ec;
var ec = new EC('secp256k1');
var xor = require('./xor_bignumber.js');

var NSlotsPerUser = 5;

function MixUser(dest) {
    this.key = ec.genKeyPair();
    this.dest = dest;
}

MixUser.prototype.getPrivate = function() {
    var priv = this.key.getPrivate();
    var d = new BigNumber(priv.toString(16), 16);
    return d;
};

MixUser.prototype.getPubX = function() {
    var pub = this.key.getPublic();
    var pub_x = new BigNumber(pub.x.toString(16), 16);
    return pub_x;
};

MixUser.prototype.getPubY = function() {
    var pub = this.key.getPublic();
    var pub_y = new BigNumber(pub.y.toString(16), 16);
    return pub_y;
};


function getByte(d, p) {
    var pos = new BigNumber(2).pow(p*8);
    var res = d.divToInt(pos).mod(256);
    return res.toNumber();
}

function setByte(d,p,v) {
    var pos = new BigNumber(2).pow(p*8);
    var res = d.add(pos.mul(v));
    return res;
}




function sha3(num) {
    var n = num.toString(16);
    while (n.length<64) n='0'+n;
    var res = ethConnector.web3.sha3(n, {encoding: 'hex'});
    return new BigNumber(res.substr(2), 16);
}

MixUser.prototype.calculateMix = function(users, seed) {
    var i,j;

    // Save parameters
    this.NUsers = users.length;
    this.NSlots = this.NUsers * NSlotsPerUser;
    this.seed = seed;

    // Initialize the mask;
    var mask = new Array(this.NSlots*2);
    for (j=0; j<mask.length; j++) mask[j] = new BigNumber(0);


    var d = this.calcDataHash();

    // Put the data in each slot
    for (i=0; i<NSlotsPerUser; i++) {
        var slot = getByte(d, 31-i);
        mask[slot*2] = d;
        mask[slot*2+1] = sha3(d);
    }

    // Calculate the mask for each user
    for (i=0; i<users.length; i++) {

        // Do not put the mask for myself
        if ((this.getPubX().equals(users[i].pubX)) &&
            (this.getPubY().equals(users[i].pubY))) continue;

        // construct the shared key with the other
        var pub = users[i].pubY.toString(16);
        while (pub.length <64) pub = "0" +pub;
        pub = users[i].pubX.toString(16) + pub;
        while (pub.length <128) pub = "0" +pub;
        pub = "04" + pub;
        var keyOther = ec.keyFromPublic(pub, 'hex');
        var shared = this.key.derive(keyOther.getPublic());

        // console.log("shared " + i + ": " + shared.toString(16));

        // Expand the key to a mask and xor with the current mask
        var c = new BigNumber(shared.toString(16),16);
        c = sha3(c);
        for (j=0; j< mask.length; j++) {
            mask[j] = xor(mask[j], c);
            c= sha3(c);
        }
    }

    var maskH = "";
    for (i=0; i<mask.length; i++) {
        var aux = mask[i].toString(16);
        while (aux.length < 64) aux = '0' + aux;
        maskH = maskH + aux;
    }

    this.mixData = mask;
    this.mixDataHash = ethConnector.web3.sha3( maskH,  {encoding: 'hex'});
};

MixUser.prototype.getHash = function() {
    return this.mixDataHash;
};

MixUser.prototype.getData = function() {
    return this.mixData;
};


MixUser.prototype.calcDataHash = function() {
        var pos = new Array(this.NSlots);
        var i;
        var res = new BigNumber(this.dest);
        var prnd;

        for (i=0; i<this.NSlots; i++) pos[i] = i;

        prnd = sha3(xor(this.getPrivate(), this.seed));

        for (i=0; i<NSlotsPerUser; i++) {
            var p = prnd.mod(this.NSlots - i).toNumber();
            res = setByte(res, 31-i, pos[p]);
            pos[p] = pos.pop();
            prnd = sha3(prnd);
        }

        // console.log(res.toString(16));

        return res;
};

module.exports = MixUser;






