/*jslint node: true */
"use strict";

var BigNumber = require('bignumber.js');

var xor_table;
var hex_table = "0123456789abcdef";
function xor(num1, num2) {
    var n1 = num1.toString(16);
    var n2 = num2.toString(16);
    var i,j;
    if (!xor_table) {
        xor_table = {};
        for (i=0; i<16; i++) {
            for (j=0; j<16; j++) {
                xor_table[hex_table[i] + hex_table[j]] = hex_table[ i ^ j];
            }
        }
    }
    var l = n1.length > n2.length ? n1.length : n2.length;
    while (n1.length <l) n1 = "0"+n1;
    while (n2.length <l) n2 = "0"+n2;
    n1 = n1.toLowerCase();
    n2 = n2.toLowerCase();
    var r = "";
    for (i=0; i<l; i++) {
        r=r + xor_table[n1[i] + n2[i]];
    }
    return new BigNumber(r,16);
}

module.exports = xor;
