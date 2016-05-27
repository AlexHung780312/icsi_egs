#!/usr/bin/env python
# -*- coding: utf-8 -*-
import argparse
import fileinput
import string

from nltk import word_tokenize

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='text normalize)', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--lang', default="english", help="for NLTK")
    args = parser.parse_args()
    # tools
    exclude = set(string.punctuation) | set(['``', '\'\''])
    #
    for line in fileinput.input():
        cols = line.strip().split(' ')
        key = str(cols[0])
        del cols[0]
        text = ' '.join(cols)
        text = text.upper().replace('.', '').replace('_', '').replace('-', ' ')
        words = [w.strip('-') for w in word_tokenize(text) if w not in exclude]
        print "%s %s" % (key, " ".join(words))
