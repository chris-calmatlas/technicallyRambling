/**
 * @param {string} word1
 * @param {string} word2
 * @return {string}
 */
var mergeAlternately = function(word1, word2) {
    let newWord = "";
    let index = 0;
    while ( index < word1.length || index < word2.length ){
        newWord += index < word1.length ? word1[index] : "";
        newWord += index < word2.length ? word2[index] : "";
        index++;
    }
    return newWord;
};