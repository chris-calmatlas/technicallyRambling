
class Solution:
    def mergeAlternately(self, word1: str, word2: str) -> str:
        newWordArray = []
        index = 0
        moreWord1 = True
        moreWord2 = True
        while moreWord1 or moreWord2:
            try:
                newWordArray.append(word1[index])
            except:
                moreWord1 = False
            try:
                newWordArray.append(word2[index])
            except:
                moreWord2 = False
            index += 1
        return "".join(newWordArray)